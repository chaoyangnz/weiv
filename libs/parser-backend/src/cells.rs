use oxc_allocator::{Allocator, TakeIn};
use oxc_ast::{ast::*, AstBuilder};
use oxc_ast_visit::{walk_mut, VisitMut};
use oxc_codegen::{Codegen, CodegenOptions};
use oxc_parser::Parser;
use oxc_semantic::{ScopeFlags, Scoping, SemanticBuilder, SymbolId};
use oxc_span::{SourceType, SPAN};
use oxc_transformer::{TransformOptions, Transformer};
use std::collections::HashSet;
use std::path::Path;

// Experimental lowering. Symbol identities come from the original parsed script;
// shadowed locals and unrelated property keys must never be changed by spelling.
pub fn lower(source: &str, path: &str, names: &[String]) -> Result<String, &'static str> {
    lower_mode(source, path, names, false, "", false)
}

pub fn lower_with_expressions(
    source: &str,
    path: &str,
    names: &[String],
    expressions: &str,
) -> Result<String, &'static str> {
    lower_mode(source, path, names, false, expressions, true)
}

pub fn validate_expression(source: &str) -> bool {
    lower_mode(
        &format!("({source});"),
        "expression.ts",
        &[],
        true,
        "",
        false,
    )
    .is_ok()
}

pub fn validate_handler_expression(source: &str) -> bool {
    lower_mode(
        &format!("({source});"),
        "expression.ts",
        &[],
        false,
        "",
        false,
    )
    .is_ok()
}

pub fn anonymous_definition(expression: &Expression<'_>) -> bool {
    match expression.get_inner_expression() {
        Expression::ArrowFunctionExpression(_) => true,
        Expression::FunctionExpression(function) => function.id.is_none(),
        Expression::ClassExpression(class) => class.id.is_none(),
        _ => false,
    }
}

// Keep the anonymous class lexical environment: assigning an inner class name
// would hide references to the previous/TDZ outer binding in user static code.
pub fn class_name_insertion(expression: &Expression<'_>, name: &str) -> Option<(u32, String)> {
    if let Expression::ClassExpression(class) = expression.get_inner_expression() {
        if class.id.is_none() {
            return Some((
                class.body.span.start + 1,
                format!(
                    "static{{__weiv_initializeClassName(this,{});}}",
                    serde_json::to_string(name).unwrap()
                ),
            ));
        }
    }
    None
}

fn initialize_class_name<'a>(ast: AstBuilder<'a>, expression: &mut Expression<'a>, name: &str) {
    if let Expression::ClassExpression(class) = expression.get_inner_expression_mut() {
        if class.id.is_none() {
            let call = ast.expression_call(
                SPAN,
                ast.expression_identifier(SPAN, "__weiv_initializeClassName"),
                None::<oxc_allocator::Box<'a, TSTypeParameterInstantiation<'a>>>,
                ast.vec_from_array([
                    Argument::from(ast.expression_this(SPAN)),
                    Argument::from(ast.expression_string_literal(
                        SPAN,
                        ast.allocator.alloc_str(name),
                        None,
                    )),
                ]),
                false,
            );
            class.body.body.insert(
                0,
                ast.class_element_static_block(
                    SPAN,
                    ast.vec1(ast.statement_expression(SPAN, call)),
                ),
            );
        }
    }
}

pub fn assignment_identifier<'s, 'a>(
    target: &'s AssignmentTarget<'a>,
) -> Option<&'s IdentifierReference<'a>> {
    simple_assignment_identifier(target.as_simple_assignment_target()?)
}

fn simple_assignment_identifier<'s, 'a>(
    target: &'s SimpleAssignmentTarget<'a>,
) -> Option<&'s IdentifierReference<'a>> {
    fn identifier<'s, 'a>(expression: &'s Expression<'a>) -> Option<&'s IdentifierReference<'a>> {
        match expression.get_inner_expression() {
            Expression::Identifier(id) => Some(id),
            _ => None,
        }
    }
    match target {
        SimpleAssignmentTarget::AssignmentTargetIdentifier(id) => Some(id),
        SimpleAssignmentTarget::TSAsExpression(wrapper) => identifier(&wrapper.expression),
        SimpleAssignmentTarget::TSSatisfiesExpression(wrapper) => identifier(&wrapper.expression),
        SimpleAssignmentTarget::TSNonNullExpression(wrapper) => identifier(&wrapper.expression),
        SimpleAssignmentTarget::TSTypeAssertion(wrapper) => identifier(&wrapper.expression),
        _ => None,
    }
}

fn lower_mode(
    source: &str,
    path: &str,
    names: &[String],
    template_only: bool,
    expressions: &str,
    component: bool,
) -> Result<String, &'static str> {
    let prepared =
        crate::declarations::prepare(source, path, names, crate::declarations::Mode::Cells)?;
    let mut combined = prepared.source;
    if !expressions.is_empty() {
        combined.push_str(&format!(
            "\n;const __weiv_templateExpressions=[{expressions}];\n"
        ));
    }
    let source = combined.as_str();
    let allocator = Allocator::default();
    let parsed = Parser::new(
        &allocator,
        source,
        SourceType::from_path(path).unwrap_or(SourceType::ts()),
    )
    .parse();
    if !parsed.errors.is_empty() {
        return Err("syntax");
    }
    let mut program = parsed.program;
    let semantic = SemanticBuilder::new().build(&program);
    let scoping = semantic.semantic.into_scoping();
    let selected: HashSet<SymbolId> = scoping
        .symbol_ids()
        .filter(|id| {
            scoping.symbol_scope_id(*id) == scoping.root_scope_id()
                && names.iter().any(|name| name == scoping.symbol_name(*id))
        })
        .collect();
    if selected.len() != names.len() {
        return Err("missing_binding");
    }
    let initialized = selected
        .iter()
        .copied()
        .filter(|id| prepared.names.contains(scoping.symbol_name(*id)))
        .collect();
    let mut visitor = Cells {
        ast: AstBuilder::new(&allocator),
        scoping: &scoping,
        selected,
        imported: program
            .body
            .iter()
            .filter_map(|statement| match statement {
                Statement::ImportDeclaration(import) if !import.source.value.ends_with(".weiv") => {
                    import.specifiers.as_ref()
                }
                _ => None,
            })
            .flat_map(|specifiers| specifiers.iter())
            .filter_map(|specifier| match specifier {
                ImportDeclarationSpecifier::ImportSpecifier(s) => s.local.symbol_id.get(),
                ImportDeclarationSpecifier::ImportDefaultSpecifier(s) => s.local.symbol_id.get(),
                ImportDeclarationSpecifier::ImportNamespaceSpecifier(s) => s.local.symbol_id.get(),
            })
            .collect(),
        initialized,
        error: None,
        template_only,
        function_depth: 0,
        in_template: false,
    };
    visitor.visit_program(&mut program);
    if let Some(error) = visitor.error {
        return Err(error);
    }
    if visitor.initialized.len() != names.len() {
        return Err("declaration");
    }
    if component {
        let ast = AstBuilder::new(&allocator);
        let mut body = ast.vec();
        for statement in program.body.take_in(&allocator) {
            match statement {
                Statement::ImportDeclaration(_) | Statement::ExportAllDeclaration(_) => {}
                Statement::ExportNamedDeclaration(mut export) => {
                    if let Some(mut declaration) = export.declaration.take() {
                        if let Declaration::VariableDeclaration(variable) = &mut declaration {
                            variable.declarations.retain(|declarator|!matches!(&declarator.id,BindingPattern::BindingIdentifier(id) if id.name=="props"));
                            if variable.declarations.is_empty() {
                                continue;
                            }
                        }
                        body.push(Statement::from(declaration));
                    }
                }
                Statement::ExportDefaultDeclaration(_) => return Err("component_default_export"),
                statement => body.push(statement),
            }
        }
        program.body = body;
    }
    // Rebuild scoping after AST edits; the original semantic tables identify
    // source references but no longer describe the generated cell accesses.
    let semantic = SemanticBuilder::new().build(&program);
    let options = TransformOptions::default();
    Transformer::new(&allocator, Path::new(path), &options)
        .build_with_scoping(semantic.semantic.into_scoping(), &mut program);
    Ok(Codegen::new()
        .with_options(CodegenOptions::default())
        .build(&program)
        .code)
}

struct Cells<'a, 's> {
    ast: AstBuilder<'a>,
    scoping: &'s Scoping,
    selected: HashSet<SymbolId>,
    imported: HashSet<SymbolId>,
    initialized: HashSet<SymbolId>,
    error: Option<&'static str>,
    template_only: bool,
    function_depth: usize,
    in_template: bool,
}

impl<'a> Cells<'a, '_> {
    fn selected_reference(&self, id: &IdentifierReference<'a>) -> bool {
        id.reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
            .is_some_and(|id| self.selected.contains(&id))
    }
    fn imported_reference(&self, id: &IdentifierReference<'a>) -> bool {
        id.reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
            .is_some_and(|id| self.imported.contains(&id))
    }
    fn value(&self, span: oxc_span::Span, name: &str) -> MemberExpression<'a> {
        self.ast.member_expression_static(
            span,
            self.ast
                .expression_identifier(span, self.ast.allocator.alloc_str(name)),
            self.ast.identifier_name(SPAN, "value"),
            false,
        )
    }
    fn unbind(&self, expr: Expression<'a>) -> Expression<'a> {
        self.ast.expression_call(
            SPAN,
            self.ast
                .expression_identifier(SPAN, "__weiv_unbindCellValue"),
            None::<oxc_allocator::Box<'a, TSTypeParameterInstantiation<'a>>>,
            self.ast.vec1(Argument::from(expr)),
            false,
        )
    }

    fn target_name(&self, target: &AssignmentTarget<'a>) -> Option<String> {
        let id = assignment_identifier(target)?;
        self.selected_reference(id).then(|| id.name.to_string())
    }

    fn target(&self, span: oxc_span::Span, name: &str) -> MemberExpression<'a> {
        let read = self.ast.expression_arrow_function(
            SPAN,
            true,
            false,
            None::<oxc_allocator::Box<'a, TSTypeParameterDeclaration<'a>>>,
            self.ast.alloc_formal_parameters(
                SPAN,
                FormalParameterKind::ArrowFormalParameters,
                self.ast.vec(),
                None::<oxc_allocator::Box<'a, FormalParameterRest<'a>>>,
            ),
            None::<oxc_allocator::Box<'a, TSTypeAnnotation<'a>>>,
            self.ast.alloc_function_body(
                SPAN,
                self.ast.vec(),
                self.ast.vec1(
                    self.ast.statement_expression(
                        SPAN,
                        self.ast
                            .expression_identifier(SPAN, self.ast.allocator.alloc_str(name)),
                    ),
                ),
            ),
        );
        self.ast.member_expression_static(
            span,
            self.ast.expression_call(
                SPAN,
                self.ast
                    .expression_identifier(SPAN, "__weiv_cellAssignmentTarget"),
                None::<oxc_allocator::Box<'a, TSTypeParameterInstantiation<'a>>>,
                self.ast.vec1(Argument::from(read)),
                false,
            ),
            self.ast.identifier_name(SPAN, "value"),
            false,
        )
    }

    fn named_value(&self, mut expression: Expression<'a>, name: &str) -> Expression<'a> {
        if !anonymous_definition(&expression) {
            return expression;
        }
        // Initialize classes directly. Object-property named evaluation differs
        // across engines and can overwrite a class's user-defined name method.
        initialize_class_name(self.ast, &mut expression, name);
        if matches!(
            expression.get_inner_expression(),
            Expression::ClassExpression(_)
        ) {
            return expression;
        }
        // Functions retain property named evaluation without an inner binding.
        let name = self.ast.allocator.alloc_str(name);
        let property = self.ast.object_property_kind_object_property(
            SPAN,
            PropertyKind::Init,
            PropertyKey::StringLiteral(self.ast.alloc_string_literal(SPAN, name, None)),
            expression,
            false,
            false,
            true,
        );
        self.ast
            .member_expression_computed(
                SPAN,
                self.ast.expression_object(SPAN, self.ast.vec1(property)),
                self.ast.expression_string_literal(SPAN, name, None),
                false,
            )
            .into()
    }
}

impl<'a> VisitMut<'a> for Cells<'a, '_> {
    fn visit_identifier_reference(&mut self, id: &mut IdentifierReference<'a>) {
        if self.in_template {
            if let Some(reference) = id
                .reference_id
                .get()
                .map(|id| self.scoping.get_reference(id))
            {
                if reference.is_write() {
                    if let Some(symbol) = reference.symbol_id() {
                        let flags = self.scoping.symbol_flags(symbol);
                        if flags.is_const_variable() || flags.is_import() {
                            self.error = Some("const_assignment");
                        } else if self.scoping.symbol_scope_id(symbol)
                            == self.scoping.root_scope_id()
                            && !self.selected.contains(&symbol)
                        {
                            self.error = Some("template_untracked_assignment");
                        }
                    } else if id.name == "props" {
                        self.error = Some("template_untracked_assignment");
                    }
                }
            }
        }
        if self.imported_reference(id) {
            if self
                .scoping
                .get_reference(id.reference_id.get().unwrap())
                .is_write()
            {
                self.error = Some("const_assignment");
            }
            id.name = self
                .ast
                .allocator
                .alloc_str(&format!("__weiv_import_{}", id.name))
                .into();
        }
    }
    fn visit_function(&mut self, function: &mut Function<'a>, flags: ScopeFlags) {
        self.function_depth += 1;
        walk_mut::walk_function(self, function, flags);
        self.function_depth -= 1;
    }
    fn visit_arrow_function_expression(&mut self, function: &mut ArrowFunctionExpression<'a>) {
        self.function_depth += 1;
        walk_mut::walk_arrow_function_expression(self, function);
        self.function_depth -= 1;
    }
    fn visit_await_expression(&mut self, expression: &mut AwaitExpression<'a>) {
        if self.function_depth == 0 {
            self.error = Some("top_level_await");
        }
        walk_mut::walk_await_expression(self, expression);
    }

    fn visit_assignment_expression(&mut self, expr: &mut AssignmentExpression<'a>) {
        if self.template_only && self.function_depth == 0 {
            self.error = Some("template_mutation");
        }
        let root = self.target_name(&expr.left);
        let normalize =
            root.is_some() && matches!(expr.operator.as_str(), "=" | "||=" | "&&=" | "??=");
        walk_mut::walk_assignment_expression(self, expr);
        if normalize {
            let value = self.named_value(
                expr.right.take_in(self.ast.allocator),
                root.as_deref().unwrap(),
            );
            expr.right = self.ast.expression_call(
                SPAN,
                self.ast
                    .expression_identifier(SPAN, "__weiv_normalizeCellValue"),
                None::<oxc_allocator::Box<'a, TSTypeParameterInstantiation<'a>>>,
                self.ast.vec1(Argument::from(value)),
                false,
            );
        }
    }
    fn visit_update_expression(&mut self, expr: &mut UpdateExpression<'a>) {
        if self.template_only && self.function_depth == 0 {
            self.error = Some("template_mutation");
        }
        walk_mut::walk_update_expression(self, expr);
    }
    fn visit_unary_expression(&mut self, expr: &mut UnaryExpression<'a>) {
        if self.template_only && self.function_depth == 0 && expr.operator.as_str() == "delete" {
            self.error = Some("template_mutation");
        }
        walk_mut::walk_unary_expression(self, expr);
    }
    fn visit_expression(&mut self, expr: &mut Expression<'a>) {
        if let Expression::Identifier(id) = expr {
            if id.name == "eval" {
                self.error = Some("dynamic_eval");
            }
            if self.selected_reference(id) {
                let reference = self.scoping.get_reference(id.reference_id.get().unwrap());
                if reference.is_write() {
                    if self
                        .scoping
                        .symbol_flags(reference.symbol_id().unwrap())
                        .is_const_variable()
                    {
                        self.error = Some("const_assignment");
                    }
                }
                *expr = if reference.is_write() {
                    self.target(id.span, id.name.as_str())
                } else {
                    self.value(id.span, id.name.as_str())
                }
                .into();
                return;
            }
        }
        walk_mut::walk_expression(self, expr);
    }
    fn visit_simple_assignment_target(&mut self, target: &mut SimpleAssignmentTarget<'a>) {
        if let Some(id) = simple_assignment_identifier(target) {
            if self.selected_reference(id) {
                let symbol = id
                    .reference_id
                    .get()
                    .and_then(|id| self.scoping.get_reference(id).symbol_id())
                    .unwrap();
                if self.scoping.symbol_flags(symbol).is_const_variable() {
                    self.error = Some("const_assignment");
                    return;
                }
                *target = self.target(id.span, id.name.as_str()).into();
                return;
            }
        }
        walk_mut::walk_simple_assignment_target(self, target);
    }
    fn visit_assignment_target_property(&mut self, property: &mut AssignmentTargetProperty<'a>) {
        if let AssignmentTargetProperty::AssignmentTargetPropertyIdentifier(shorthand) = property {
            if self.selected_reference(&shorthand.binding) {
                let id = &shorthand.binding;
                let symbol = self
                    .scoping
                    .get_reference(id.reference_id.get().unwrap())
                    .symbol_id()
                    .unwrap();
                if self.scoping.symbol_flags(symbol).is_const_variable() {
                    self.error = Some("const_assignment");
                    return;
                }
                let name = id.name.to_string();
                let span = id.span;
                let target: AssignmentTarget<'a> = self.target(span, &name).into();
                let binding = if let Some(mut initial) = shorthand.init.take() {
                    self.visit_expression(&mut initial);
                    self.ast
                        .assignment_target_maybe_default_assignment_target_with_default(
                            shorthand.span,
                            target,
                            self.named_value(initial, &name),
                        )
                } else {
                    target.into()
                };
                *property = self
                    .ast
                    .assignment_target_property_assignment_target_property_property(
                        shorthand.span,
                        self.ast.property_key_static_identifier(
                            span,
                            self.ast.allocator.alloc_str(&name),
                        ),
                        binding,
                        false,
                    );
                return;
            }
        }
        walk_mut::walk_assignment_target_property(self, property);
    }
    fn visit_assignment_target_with_default(
        &mut self,
        target: &mut AssignmentTargetWithDefault<'a>,
    ) {
        let name = self.target_name(&target.binding);
        walk_mut::walk_assignment_target_with_default(self, target);
        if let Some(name) = name {
            target.init = self.named_value(target.init.take_in(self.ast.allocator), &name);
        }
    }
    fn visit_variable_declaration(&mut self, declaration: &mut VariableDeclaration<'a>) {
        if declaration.declare {
            self.error = Some("ambient_declaration");
        }
        walk_mut::walk_variable_declaration(self, declaration);
    }
    fn visit_variable_declarator(&mut self, declaration: &mut VariableDeclarator<'a>) {
        // Recurse into initializers before wrapping, so references to earlier
        // declarations and self-references preserve their lexical meaning.
        let previous = self.in_template;
        if matches!(&declaration.id,BindingPattern::BindingIdentifier(id) if id.name=="__weiv_templateExpressions")
        {
            self.in_template = true;
        }
        walk_mut::walk_variable_declarator(self, declaration);
        self.in_template = previous;
        if let BindingPattern::BindingIdentifier(id) = &declaration.id {
            if let Some(symbol) = id.symbol_id.get().filter(|id| self.selected.contains(id)) {
                if declaration.kind != VariableDeclarationKind::Let
                    && declaration.kind != VariableDeclarationKind::Const
                {
                    self.error = Some("declaration_kind");
                    return;
                }
                self.initialized.insert(symbol);
                let arguments = declaration.init.take().map_or_else(
                    || self.ast.vec(),
                    |initial| {
                        self.ast
                            .vec1(Argument::from(self.named_value(initial, id.name.as_str())))
                    },
                );
                declaration.init = Some(self.ast.expression_call(
                    SPAN,
                    self.ast.expression_identifier(SPAN, "__weiv_createCell"),
                    None::<oxc_allocator::Box<'a, TSTypeParameterInstantiation<'a>>>,
                    arguments,
                    false,
                ));
            }
        }
    }
    fn visit_object_property(&mut self, property: &mut ObjectProperty<'a>) {
        let expanded = matches!(&property.value, Expression::Identifier(id) if self.selected_reference(id) || self.imported_reference(id));
        walk_mut::walk_object_property(self, property);
        if expanded {
            property.shorthand = false;
        }
    }
    fn visit_call_expression(&mut self, call: &mut CallExpression<'a>) {
        // Direct eval can access bindings by string, which this transform cannot
        // account for. Reject it rather than accept a partially tracked script.
        if matches!(&call.callee, Expression::Identifier(id) if id.name == "eval") {
            self.error = Some("dynamic_eval");
        }
        let unbind = matches!(call.callee.get_inner_expression(), Expression::Identifier(id) if self.selected_reference(id))
            || matches!(
                call.callee.get_inner_expression(),
                Expression::SequenceExpression(_)
            );
        walk_mut::walk_call_expression(self, call);
        if unbind {
            call.callee = self.unbind(call.callee.take_in(self.ast.allocator));
        }
    }
    fn visit_tagged_template_expression(&mut self, tagged: &mut TaggedTemplateExpression<'a>) {
        let unbind = matches!(tagged.tag.get_inner_expression(), Expression::Identifier(id) if self.selected_reference(id))
            || matches!(
                tagged.tag.get_inner_expression(),
                Expression::SequenceExpression(_)
            );
        walk_mut::walk_tagged_template_expression(self, tagged);
        if unbind {
            tagged.tag = self.unbind(tagged.tag.take_in(self.ast.allocator));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::lower;
    #[test]
    fn imports_remain_live_without_renaming_shadowed_locals() {
        let code = lower("import {count} from './state'; import Child from './Child.weiv'; let own=0; function read(){return {count}} function shadow(count){return count} function component(){return Child}", "state.ts", &["own".into()]).unwrap();
        assert!(code.contains("count: __weiv_import_count"));
        assert!(code.contains("return count;"));
        assert!(code.contains("return Child;"));
        assert!(!code.contains("__weiv_import_Child"));
    }
    #[test]
    fn lexical_shadowing_and_expression_writes() {
        let code = lower("let count = 0; function f(count) { return ++count; } const obj = {count}; count += 2; const old = count++;", "state.ts", &["count".into()]).unwrap();
        assert!(code.contains("count = __weiv_createCell(0)"));
        assert!(code.contains("return ++count;"));
        assert!(code.contains("count: count.value"));
        assert!(code.contains("__weiv_cellAssignmentTarget(() => count).value += 2"));
        assert!(code.contains("old = __weiv_cellAssignmentTarget(() => count).value++"));
    }
    #[test]
    fn uninitialized_bindings_do_not_capture_shadowed_undefined() {
        let code = lower(
            "let undefined=12; let count; const label='__weiv_literal';",
            "state.ts",
            &["count".into()],
        )
        .unwrap();
        assert!(code.contains("count = __weiv_createCell()"));
        assert!(!code.contains("__weiv_createCell(undefined)"));
    }

    #[test]
    fn patterns_and_loops_select_lexical_targets_and_preserve_default_names() {
        let code = lower("let count=0; ({count=()=>count}={}); ({value:count=class {static label=this.name}}={}); for([count] of [[1]]){} function shadow(count){({count}={count:2})}", "state.ts", &["count".into()]).unwrap();
        assert!(code.contains("count: __weiv_cellAssignmentTarget(() => count).value"));
        assert!(code.contains("for ([__weiv_cellAssignmentTarget(() => count).value]"));
        assert!(code.contains("[\"count\"]: () => count.value"));
        assert!(code.contains("__weiv_initializeClassName(this, \"count\")"));
        assert!(!code.contains("[\"count\"]: class"));
        assert!(code.contains("({count} = { count: 2 })"), "{code}");
    }

    #[test]
    fn render_expressions_reject_immediate_mutation_and_allow_deferred_callbacks() {
        for expression in [
            "count++",
            "count = 1",
            "delete state.item",
            "eval('count++')",
        ] {
            assert!(!super::validate_expression(expression));
        }
        assert!(super::validate_expression("increment"));
        assert!(super::validate_expression("increment(2)"));
        assert!(super::validate_expression(
            "items.map(item => item.name).join(',')"
        ));
        assert!(super::validate_expression("()=>count++"));
        assert!(super::validate_expression(
            "async()=>{count++;await next();count++}"
        ));
    }

    #[test]
    fn template_closures_reuse_root_lowering_and_reject_readonly_or_untracked_writes() {
        let lowered = super::lower_with_expressions(
            "let count=0;",
            "s.ts",
            &["count".into()],
            "(__weiv_context)=>()=>count++",
        )
        .unwrap();
        assert!(lowered.contains("__weiv_cellAssignmentTarget(() => count).value++"));
        for (source, names, expression, error) in [
            (
                "const count=0;",
                vec!["count".into()],
                "()=>count++",
                "const_assignment",
            ),
            (
                "import {count} from './state';",
                vec![],
                "()=>count++",
                "const_assignment",
            ),
            (
                "let count=0;",
                vec![],
                "()=>count++",
                "template_untracked_assignment",
            ),
            (
                "function count(){return 0}",
                vec![],
                "()=>count=()=>1",
                "template_untracked_assignment",
            ),
            (
                "let count=0;",
                vec!["count".into()],
                "(__weiv_context)=>{const row=__weiv_context.row;return ()=>row++}",
                "const_assignment",
            ),
        ] {
            assert_eq!(
                super::lower_with_expressions(source, "s.ts", &names, expression).unwrap_err(),
                error
            );
        }
    }

    #[test]
    fn unsupported_forms_fail_closed() {
        for source in [
            "var count = 0;",
            "var {count} = {count: 0};",
            "const count=0; ({count}={count:1});",
            "let count=0; eval('count++');",
            "let count=0; (eval)('count++');",
            "declare let count:number;",
            "let count=await Promise.resolve(1);",
            "const count=0; (count as any)++;",
        ] {
            assert!(
                lower(source, "state.ts", &["count".into()]).is_err(),
                "{source}"
            );
        }
    }
}
