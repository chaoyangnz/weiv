//! Experimental module lowering keeps actual ESM bindings and public exports.
//! Its caller owns canonical module selection and companion-module identity.
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::{walk, Visit};
use oxc_codegen::Codegen;
use oxc_parser::Parser;
use oxc_semantic::{Scoping, SemanticBuilder, SymbolId};
use oxc_span::{GetSpan, SourceType, Span};
use oxc_transformer::{TransformOptions, Transformer};
use std::collections::HashSet;
use std::path::Path;

struct Wrapper {
    span: Span,
    before: String,
    after: String,
}
struct Lower<'s> {
    scoping: &'s Scoping,
    selected: HashSet<SymbolId>,
    wrappers: Vec<Wrapper>,
    error: Option<&'static str>,
    in_write: bool,
}
impl Lower<'_> {
    fn selected(&self, id: &IdentifierReference<'_>) -> bool {
        id.reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
            .is_some_and(|id| self.selected.contains(&id))
    }
    fn normalize(&mut self, expression: &Expression<'_>) {
        // Calls around anonymous functions/classes change inferred .name and
        // class static initialization. Retain their original named evaluation.
        if matches!(
            expression.get_inner_expression(),
            Expression::FunctionExpression(_)
                | Expression::ArrowFunctionExpression(_)
                | Expression::ClassExpression(_)
        ) {
            return;
        }
        self.wrappers.push(Wrapper {
            span: expression.span(),
            before: "__weiv_normalizeCellValue(".into(),
            after: ")".into(),
        });
    }
    fn publish_write(&mut self, id: &IdentifierReference<'_>, span: Span) {
        let name = id.name.as_str();
        self.wrappers.push(Wrapper {
            span,
            before: format!("__weiv_afterModuleWrite(() => __weiv_module, {name:?}, ("),
            after: format!("), () => {name})"),
        });
    }

    fn publish_target(&mut self, id: &IdentifierReference<'_>, shorthand: bool) {
        let symbol = self
            .scoping
            .get_reference(id.reference_id.get().unwrap())
            .symbol_id()
            .unwrap();
        if self.scoping.symbol_flags(symbol).is_const_variable() {
            self.error = Some("const_assignment");
            return;
        }
        let name = id.name.as_str();
        self.wrappers.push(Wrapper {span:id.span,before:format!("{}__weiv_assignmentTarget(() => {name}, __weiv_next => __weiv_afterModuleWrite(() => __weiv_module, {name:?}, (",if shorthand {format!("{name}: ")} else {String::new()}),after:format!(" = __weiv_normalizeCellValue(__weiv_next)), () => {name})).value")});
    }

    fn named_default(&mut self, id: &IdentifierReference<'_>, value: &Expression<'_>) {
        if crate::cells::anonymous_definition(value) {
            let name = id.name.as_str();
            if let Some((position, statement)) = crate::cells::class_name_insertion(value, name) {
                self.wrappers.push(Wrapper {
                    span: Span::new(position, position),
                    before: statement,
                    after: String::new(),
                });
                return;
            }
            self.wrappers.push(Wrapper {
                span: value.span(),
                before: format!("({{[{name:?}]: ("),
                after: format!(")}})[{name:?}]"),
            });
        }
    }
}
impl<'a> Visit<'a> for Lower<'_> {
    fn visit_expression(&mut self, expression: &Expression<'a>) {
        match expression {
            Expression::AssignmentExpression(assignment) => {
                if let Some(id) = crate::cells::assignment_identifier(&assignment.left) {
                    if self.selected(id) {
                        if self
                            .scoping
                            .symbol_flags(
                                self.scoping
                                    .get_reference(id.reference_id.get().unwrap())
                                    .symbol_id()
                                    .unwrap(),
                            )
                            .is_const_variable()
                        {
                            self.error = Some("const_assignment");
                        }
                        self.publish_write(id, assignment.span);
                        if matches!(assignment.operator.as_str(), "=" | "||=" | "&&=" | "??=") {
                            self.normalize(&assignment.right);
                        }
                        let previous = self.in_write;
                        self.in_write = true;
                        self.visit_assignment_target(&assignment.left);
                        self.in_write = previous;
                        self.visit_expression(&assignment.right);
                        return;
                    }
                }
            }
            Expression::UpdateExpression(update) => {
                if let SimpleAssignmentTarget::AssignmentTargetIdentifier(id) = &update.argument {
                    if self.selected(id) {
                        if self
                            .scoping
                            .symbol_flags(
                                self.scoping
                                    .get_reference(id.reference_id.get().unwrap())
                                    .symbol_id()
                                    .unwrap(),
                            )
                            .is_const_variable()
                        {
                            self.error = Some("const_assignment");
                        }
                        self.publish_write(id, update.span);
                        return;
                    }
                }
            }
            _ => {}
        }
        walk::walk_expression(self, expression);
    }
    fn visit_identifier_reference(&mut self, id: &IdentifierReference<'a>) {
        if id.name == "eval" {
            self.error = Some("dynamic_eval");
        }
        if self.selected(id)
            && !self.in_write
            && self
                .scoping
                .get_reference(id.reference_id.get().unwrap())
                .is_write()
        {
            self.publish_target(id, false);
        }
    }

    fn visit_assignment_target_property_identifier(
        &mut self,
        property: &AssignmentTargetPropertyIdentifier<'a>,
    ) {
        if self.selected(&property.binding) && !self.in_write {
            self.publish_target(&property.binding, true);
            if let Some(initial) = &property.init {
                self.named_default(&property.binding, initial);
                self.visit_expression(initial);
            }
        } else {
            walk::walk_assignment_target_property_identifier(self, property);
        }
    }

    fn visit_assignment_target_with_default(&mut self, target: &AssignmentTargetWithDefault<'a>) {
        if let Some(id) =
            crate::cells::assignment_identifier(&target.binding).filter(|id| self.selected(id))
        {
            self.named_default(id, &target.init);
        }
        walk::walk_assignment_target_with_default(self, target);
    }
}

pub fn lower(
    source: &str,
    path: &str,
    companion: &str,
    names: &[String],
) -> Result<String, &'static str> {
    let prepared =
        crate::declarations::prepare(source, path, names, crate::declarations::Mode::Module)?;
    let source = prepared.source.as_str();
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(path).unwrap_or(SourceType::ts());
    let parsed = Parser::new(&allocator, source, source_type).parse();
    if !parsed.errors.is_empty() {
        return Err("syntax");
    }
    let semantic = SemanticBuilder::new()
        .with_check_syntax_error(true)
        .build(&parsed.program);
    if !semantic.errors.is_empty() {
        return Err("syntax");
    }
    let scoping = semantic.semantic.into_scoping();
    let selected: HashSet<_> = scoping
        .symbol_ids()
        .filter(|id| {
            scoping.symbol_scope_id(*id) == scoping.root_scope_id()
                && names.iter().any(|name| name == scoping.symbol_name(*id))
        })
        .collect();
    if selected.len() != names.len() {
        return Err("missing_binding");
    }
    let mut lower = Lower {
        scoping: &scoping,
        selected,
        wrappers: Vec::new(),
        error: None,
        in_write: false,
    };
    let mut declarations = prepared.names;
    let mut inserts = Vec::<(usize, String)>::new();
    for statement in &parsed.program.body {
        let declaration = match statement {
            Statement::VariableDeclaration(declaration) => Some(declaration.as_ref()),
            Statement::ExportNamedDeclaration(export) => match &export.declaration {
                Some(Declaration::VariableDeclaration(declaration)) => Some(declaration.as_ref()),
                _ => None,
            },
            _ => None,
        };
        if let Some(declaration) = declaration {
            let mut publish = String::new();
            for declarator in &declaration.declarations {
                if let BindingPattern::BindingIdentifier(id) = &declarator.id {
                    if id
                        .symbol_id
                        .get()
                        .is_some_and(|id| lower.selected.contains(&id))
                    {
                        if declaration.declare {
                            return Err("ambient_declaration");
                        }
                        if !matches!(
                            declaration.kind,
                            VariableDeclarationKind::Const | VariableDeclarationKind::Let
                        ) {
                            return Err("declaration_kind");
                        }
                        declarations.insert(id.name.to_string());
                        if let Some(init) = &declarator.init {
                            lower.normalize(init);
                        }
                        publish.push_str(&format!(
                            "\n__weiv_module.publish({:?}, {});",
                            id.name.as_str(),
                            id.name
                        ));
                    }
                }
            }
            if !publish.is_empty() {
                inserts.push((statement.span().end as usize, format!(";{publish}\n")));
            }
        }
    }
    if declarations.len() != names.len() {
        return Err("declaration");
    }
    lower.visit_program(&parsed.program);
    if let Some(error) = lower.error {
        return Err(error);
    }
    // Wrappers nest in source order. Identical spans (an assignment initializer)
    // keep initializer normalization outside write publication.
    let mut events = Vec::<(usize, bool, usize, String)>::new();
    for (order, wrapper) in lower.wrappers.iter().enumerate() {
        events.push((
            wrapper.span.start as usize,
            true,
            order,
            wrapper.before.clone(),
        ));
        events.push((
            wrapper.span.end as usize,
            false,
            order,
            wrapper.after.clone(),
        ));
    }
    events.sort_by(|a, b| {
        a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)).then_with(|| {
            if a.1 {
                lower.wrappers[b.2]
                    .span
                    .end
                    .cmp(&lower.wrappers[a.2].span.end)
                    .then(a.2.cmp(&b.2))
            } else {
                lower.wrappers[b.2]
                    .span
                    .start
                    .cmp(&lower.wrappers[a.2].span.start)
                    .then(b.2.cmp(&a.2))
            }
        })
    });
    // Publish after all expression wrappers at the declaration's end.
    for (position, text) in inserts {
        events.push((position, true, usize::MAX, text));
    }
    events.sort_by_key(|event| event.0); // stable: preserve nesting order above
    let mut output = format!("import {{normalizeCellValue as __weiv_normalizeCellValue, afterModuleWrite as __weiv_afterModuleWrite, assignmentTarget as __weiv_assignmentTarget, initialModuleValue as __weiv_initialModuleValue, bindingObject as __weiv_bindingObject, bindingIterator as __weiv_bindingIterator, initializeClassName as __weiv_initializeClassName}} from 'weiv:cells';\nimport {{moduleState as __weiv_module}} from {};\n", serde_json::to_string(companion).unwrap());
    let mut previous = 0;
    for (position, _, _, text) in events {
        output.push_str(&source[previous..position]);
        output.push_str(&text);
        previous = position;
    }
    output.push_str(&source[previous..]);
    let parsed = Parser::new(&allocator, &output, source_type).parse();
    if !parsed.errors.is_empty() {
        return Err("generated_syntax");
    }
    let mut program = parsed.program;
    let semantic = SemanticBuilder::new()
        .with_check_syntax_error(true)
        .build(&program);
    if !semantic.errors.is_empty() {
        return Err("generated_syntax");
    }
    Transformer::new(&allocator, Path::new(path), &TransformOptions::default())
        .build_with_scoping(semantic.semantic.into_scoping(), &mut program);
    Ok(Codegen::new().build(&program).code)
}

#[cfg(test)]
mod tests {
    use super::lower;
    #[test]
    fn esm_bindings_stay_public_and_writes_publish_after_evaluation() {
        let output = lower("export let count=0; export const state={count:0}; export function next(){return count++} export {count as value}; export default count;", "state.ts", "./state.publisher.mjs", &["count".into(), "state".into()]).unwrap();
        assert!(output.contains("export let count"));
        assert!(output.contains("export const state"));
        assert!(output.contains("count++"));
        assert!(output.contains("() => count"));
        assert!(output.contains("export default count"));
    }
    #[test]
    fn unsupported_writes_fail_closed_and_named_evaluation_stays_intact() {
        assert!(lower(
            "const count=0; for(count of [1]){}",
            "s.ts",
            "./p.mjs",
            &["count".into()]
        )
        .is_err());
        assert!(lower(
            "const count=0; count++",
            "s.ts",
            "./p.mjs",
            &["count".into()]
        )
        .is_err());
        let output=lower("export let fn=()=>0; fn=function(){}; export const cls=class {static label=this.name};", "s.ts", "./p.mjs", &["fn".into(), "cls".into()]).unwrap();
        assert!(output.contains("fn = () => 0"));
        assert!(output.contains("fn = function()"));
        assert!(output.contains("cls = class"));
    }
}
