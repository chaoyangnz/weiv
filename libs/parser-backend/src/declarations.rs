//! Preserve native lexical binding initialization while extracting patterns one
//! value at a time. The final elision resumes cleanup after the last user binding.
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::{walk, Visit};
use oxc_parser::Parser;
use oxc_semantic::{ScopeFlags, SemanticBuilder};
use oxc_span::{GetSpan, SourceType, Span};
use std::collections::HashSet;

pub struct Prepared {
    pub source: String,
    pub names: HashSet<String>,
}

#[derive(Clone, Copy)]
pub enum Mode {
    Cells,
    Module,
}

// Validate user identifiers before introducing compiler-owned names. References
// as well as declarations are checked, including unresolved global references.
struct Guard {
    error: Option<&'static str>,
    depth: usize,
    block_await: bool,
}
impl<'a> Visit<'a> for Guard {
    fn visit_identifier_reference(&mut self, id: &IdentifierReference<'a>) {
        if id.name.starts_with("__weiv_") {
            self.error = Some("reserved_identifier");
        }
        if id.name == "eval" {
            self.error = Some("dynamic_eval");
        }
    }
    fn visit_binding_identifier(&mut self, id: &BindingIdentifier<'a>) {
        if id.name.starts_with("__weiv_") {
            self.error = Some("reserved_identifier");
        }
    }
    fn visit_function(&mut self, f: &Function<'a>, flags: ScopeFlags) {
        self.depth += 1;
        walk::walk_function(self, f, flags);
        self.depth -= 1;
    }
    fn visit_arrow_function_expression(&mut self, f: &ArrowFunctionExpression<'a>) {
        self.depth += 1;
        walk::walk_arrow_function_expression(self, f);
        self.depth -= 1;
    }
    fn visit_await_expression(&mut self, e: &AwaitExpression<'a>) {
        if self.block_await && self.depth == 0 {
            self.error = Some("top_level_await");
        }
        walk::walk_await_expression(self, e);
    }
    fn visit_for_of_statement(&mut self, statement: &ForOfStatement<'a>) {
        if self.block_await && self.depth == 0 && statement.r#await {
            self.error = Some("top_level_await");
        }
        walk::walk_for_of_statement(self, statement);
    }
}

struct Pattern<'s> {
    source: &'s str,
    selected: &'s [String],
    mode: Mode,
    bindings: Vec<String>,
    prepared: HashSet<String>,
    thunks: Vec<String>,
    body: String,
    serial: usize,
}
impl Pattern<'_> {
    fn text(&self, span: Span) -> &str {
        &self.source[span.start as usize..span.end as usize]
    }
    fn temp(&mut self) -> String {
        let name = format!("__weiv_pattern_{}", self.serial);
        self.serial += 1;
        name
    }
    fn thunk(&mut self, expr: &Expression<'_>, name: Option<&str>) -> String {
        let mut value = self.text(expr.span()).to_string();
        let class = matches!(expr.get_inner_expression(), Expression::ClassExpression(class) if class.id.is_none());
        if let Some((position, statement)) =
            name.and_then(|name| crate::cells::class_name_insertion(expr, name))
        {
            value.insert_str((position - expr.span().start) as usize, &statement);
        }
        let value = if let Some(name) =
            name.filter(|_| !class && crate::cells::anonymous_definition(expr))
        {
            let key = serde_json::to_string(name).unwrap();
            format!("({{[{key}]:({value})}})[{key}]")
        } else {
            value
        };
        let index = self.thunks.len();
        self.thunks.push(format!("()=>({value})"));
        format!("__weiv_thunks[{index}]()")
    }
    fn binding(&mut self, pattern: &BindingPattern<'_>, value: String) {
        match pattern {
            BindingPattern::BindingIdentifier(id) => {
                let name = id.name.to_string();
                self.bindings.push(name.clone());
                let selected = self.selected.contains(&name);
                if selected {
                    self.prepared.insert(name.clone());
                }
                let value = if selected {
                    match self.mode {
                    Mode::Cells=>format!("__weiv_createCell({value})"),
                    Mode::Module=>format!("__weiv_initialModuleValue(__weiv_module,{name:?},__weiv_normalizeCellValue({value}))"),
                }
                } else {
                    value
                };
                self.body.push_str(&format!("yield ({value});\n"));
            }
            BindingPattern::AssignmentPattern(default) => {
                let name = match &default.left {
                    BindingPattern::BindingIdentifier(id) => Some(id.name.as_str()),
                    _ => None,
                };
                let fallback = self.thunk(&default.right, name);
                let temp = self.temp();
                self.body.push_str(&format!("const {temp}=({value});\n"));
                self.binding(
                    &default.left,
                    format!("{temp}===void 0?({fallback}):{temp}"),
                );
            }
            BindingPattern::ObjectPattern(object) => {
                let temp = self.temp();
                self.body
                    .push_str(&format!("const {temp}=__weiv_bindingObject({value});\n"));
                for property in &object.properties {
                    let key = if property.computed {
                        // PropertyKey inherits Expression; spans retain the exact
                        // expression, including TypeScript wrappers.
                        let text = self.text(property.key.span()).to_string();
                        let index = self.thunks.len();
                        self.thunks.push(format!("()=>({text})"));
                        format!("__weiv_thunks[{index}]()")
                    } else {
                        match &property.key {
                            PropertyKey::StaticIdentifier(id) => format!("{:?}", id.name.as_str()),
                            _ => self.text(property.key.span()).to_string(),
                        }
                    };
                    self.binding(&property.value, format!("{temp}.get({key})"));
                }
                if let Some(rest) = &object.rest {
                    self.binding(&rest.argument, format!("{temp}.rest()"));
                }
            }
            BindingPattern::ArrayPattern(array) => {
                let temp = self.temp();
                self.body.push_str(&format!(
                    "const {temp}=__weiv_bindingIterator({value});\ntry {{\n"
                ));
                for element in &array.elements {
                    if let Some(element) = element {
                        self.binding(element, format!("{temp}.step()"));
                    } else {
                        self.body.push_str(&format!("{temp}.skip();\n"));
                    }
                }
                if let Some(rest) = &array.rest {
                    self.binding(&rest.argument, format!("{temp}.rest()"));
                }
                self.body.push_str(&format!("}} catch(__weiv_error) {{ {temp}.close(true); throw __weiv_error; }} finally {{ {temp}.close(false); }}\n"));
            }
        }
    }
}

pub fn prepare(
    source: &str,
    path: &str,
    selected: &[String],
    mode: Mode,
) -> Result<Prepared, &'static str> {
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
    let semantic = SemanticBuilder::new().build(&parsed.program);
    let scoping = semantic.semantic.into_scoping();
    let mut guard = Guard {
        error: None,
        depth: 0,
        block_await: matches!(mode, Mode::Cells),
    };
    guard.visit_program(&parsed.program);
    if let Some(error) = guard.error {
        return Err(error);
    }
    let mut edits = Vec::new();
    let mut names = HashSet::new();
    for statement in &parsed.program.body {
        let declaration = match statement {
            Statement::VariableDeclaration(d) => Some(d.as_ref()),
            Statement::ExportNamedDeclaration(e) => match &e.declaration {
                Some(Declaration::VariableDeclaration(d)) => Some(d.as_ref()),
                _ => None,
            },
            _ => None,
        };
        let Some(declaration) = declaration else {
            continue;
        };
        for declarator in &declaration.declarations {
            if matches!(declarator.id, BindingPattern::BindingIdentifier(_)) {
                continue;
            }
            let mut bound = Vec::new();
            crate::collect_binding_names(&declarator.id, &mut bound);
            if !bound.iter().any(|(name, _, _)| selected.contains(name)) {
                continue;
            }
            let mut pattern_guard = Guard {
                error: None,
                depth: 0,
                block_await: true,
            };
            pattern_guard.visit_binding_pattern(&declarator.id);
            if let Some(error) = pattern_guard.error {
                return Err(error);
            }
            if declaration.declare {
                return Err("ambient_declaration");
            }
            if !matches!(
                declaration.kind,
                VariableDeclarationKind::Let | VariableDeclarationKind::Const
            ) {
                return Err("declaration_kind");
            }
            // Only actual root lexical declarations participate.
            if !scoping.symbol_ids().any(|id| {
                scoping.symbol_scope_id(id) == scoping.root_scope_id()
                    && selected.iter().any(|name| name == scoping.symbol_name(id))
            }) {
                continue;
            }
            let Some(init) = &declarator.init else {
                return Err("declaration");
            };
            let mut pattern = Pattern {
                source,
                selected,
                mode,
                bindings: Vec::new(),
                prepared: HashSet::new(),
                thunks: Vec::new(),
                body: String::new(),
                serial: 0,
            };
            pattern.binding(&declarator.id, "__weiv_source".into());
            let bindings = pattern.bindings.join(",");
            let flat = if bindings.is_empty() {
                ",".into()
            } else {
                format!("{bindings},,")
            };
            let replacement = format!(
                "[{flat}] = (function*(__weiv_source,__weiv_thunks){{\n{}\n}})(({}),[{}])",
                pattern.body,
                pattern.text(init.span()),
                pattern.thunks.join(",")
            );
            names.extend(pattern.prepared);
            edits.push((declarator.span, replacement));
        }
    }
    let mut output = String::new();
    let mut end = 0;
    for (span, replacement) in edits {
        output.push_str(&source[end..span.start as usize]);
        output.push_str(&replacement);
        end = span.end as usize;
    }
    output.push_str(&source[end..]);
    if matches!(mode, Mode::Module) {
        output = split_module_declarations(&output, path, selected)?;
    }
    Ok(Prepared {
        source: output,
        names,
    })
}

fn split_module_declarations(
    source: &str,
    path: &str,
    selected: &[String],
) -> Result<String, &'static str> {
    let allocator = Allocator::default();
    let parsed = Parser::new(
        &allocator,
        source,
        SourceType::from_path(path).unwrap_or(SourceType::ts()),
    )
    .parse();
    if !parsed.errors.is_empty() {
        return Err("generated_syntax");
    }
    let mut output = String::new();
    let mut end = 0;
    for statement in &parsed.program.body {
        let (declaration, exported) = match statement {
            Statement::VariableDeclaration(d) => (d.as_ref(), false),
            Statement::ExportNamedDeclaration(e) => match &e.declaration {
                Some(Declaration::VariableDeclaration(d)) => (d.as_ref(), true),
                _ => continue,
            },
            _ => continue,
        };
        if declaration.declarations.len() < 2
            || !matches!(
                declaration.kind,
                VariableDeclarationKind::Let | VariableDeclarationKind::Const
            )
        {
            continue;
        }
        let mut names = Vec::new();
        for d in &declaration.declarations {
            crate::collect_binding_names(&d.id, &mut names)
        }
        if !names.iter().any(|(name, _, _)| selected.contains(name)) {
            continue;
        }
        if declaration.declare {
            return Err("ambient_declaration");
        }
        let span = statement.span();
        output.push_str(&source[end..span.start as usize]);
        for d in &declaration.declarations {
            output.push_str(if exported { "export " } else { "" });
            output.push_str(if declaration.kind == VariableDeclarationKind::Let {
                "let "
            } else {
                "const "
            });
            output.push_str(&source[d.span.start as usize..d.span.end as usize]);
            output.push_str(";\n");
        }
        end = span.end as usize;
    }
    output.push_str(&source[end..]);
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::{prepare, Mode};
    #[test]
    fn user_references_cannot_capture_generated_binding_helpers() {
        for source in [
            "let count=__weiv_source;",
            "let {count}=__weiv_bindingObject({count:1});",
            "let {count=()=>__weiv_thunks}={};",
            "let count=0; function hidden(__weiv_source){return __weiv_source}",
        ] {
            assert!(
                matches!(
                    prepare(source, "s.ts", &["count".into()], Mode::Cells),
                    Err("reserved_identifier")
                ),
                "{source}"
            );
        }
        assert!(prepare(
            "let {count='__weiv_source'}={}",
            "s.ts",
            &["count".into()],
            Mode::Cells
        )
        .is_ok());
    }

    #[test]
    fn module_rhs_await_remains_lexical_but_pattern_await_fails_explicitly() {
        assert!(matches!(
            prepare(
                "let count=0;for await(const value of []){count=value}",
                "s.mjs",
                &["count".into()],
                Mode::Cells
            ),
            Err("top_level_await")
        ));
        assert!(prepare(
            "export let {count}=await Promise.resolve({count:1})",
            "s.ts",
            &["count".into()],
            Mode::Module
        )
        .is_ok());
        assert!(matches!(
            prepare(
                "export let {count=await Promise.resolve(1)}={}",
                "s.ts",
                &["count".into()],
                Mode::Module
            ),
            Err("top_level_await")
        ));
    }

    #[test]
    fn unselected_native_patterns_are_not_rewritten() {
        let source = "let {untouched}=source;let count=0";
        let result = prepare(source, "s.ts", &["count".into()], Mode::Cells).unwrap();
        assert_eq!(result.source, source);
        assert!(result.names.is_empty());
    }
}
