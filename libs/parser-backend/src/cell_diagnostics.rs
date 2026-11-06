//! Failure-only locations from original syntax, before declaration extraction or
//! transpilation changes offsets. Only report the reason the real lowerer rejects.
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::{walk, Visit};
use oxc_parser::Parser;
use oxc_semantic::{ScopeFlags, Scoping, SemanticBuilder, SymbolId};
use oxc_span::{SourceType, Span};
use serde::Serialize;
use std::collections::HashSet;

#[derive(Serialize)]
pub struct Diagnostic {
    pub reason: &'static str,
    pub span_start: u32,
    pub span_end: u32,
    pub message: Option<String>,
}

pub fn inspect(source: &str, path: &str, names: &[String], module: bool) -> Vec<Diagnostic> {
    let result = if module {
        crate::module_cells::lower(source, path, "./diagnostic.publisher.mjs", names)
    } else {
        crate::cells::lower_with_expressions(source, path, names, "")
    };
    let Err(reason) = result else {
        return Vec::new();
    };
    let allocator = Allocator::default();
    let parsed = Parser::new(
        &allocator,
        source,
        SourceType::from_path(path).unwrap_or(SourceType::ts()),
    )
    .parse();
    if !parsed.errors.is_empty() {
        return parsed
            .errors
            .iter()
            .filter_map(|error| {
                let label = error.labels.as_ref()?.first()?;
                Some(Diagnostic {
                    reason: "syntax",
                    span_start: label.offset() as u32,
                    span_end: (label.offset() + label.len()) as u32,
                    message: Some(error.to_string()),
                })
            })
            .collect();
    }
    let semantic = SemanticBuilder::new()
        .with_check_syntax_error(module)
        .build(&parsed.program);
    if reason == "syntax" {
        return semantic
            .errors
            .iter()
            .filter_map(|error| {
                let label = error.labels.as_ref()?.first()?;
                Some(Diagnostic {
                    reason: "syntax",
                    span_start: label.offset() as u32,
                    span_end: (label.offset() + label.len()) as u32,
                    message: Some(error.to_string()),
                })
            })
            .collect();
    }
    let scoping = semantic.semantic.into_scoping();
    let selected = scoping
        .symbol_ids()
        .filter(|id| {
            scoping.symbol_scope_id(*id) == scoping.root_scope_id()
                && names.iter().any(|name| name == scoping.symbol_name(*id))
        })
        .collect();
    let mut probe = Probe {
        scoping: &scoping,
        selected,
        module,
        reason,
        depth: 0,
        pattern_depth: None,
        diagnostics: Vec::new(),
    };
    probe.visit_program(&parsed.program);
    probe
        .diagnostics
        .sort_by_key(|entry| (entry.span_start, entry.span_end));
    probe
        .diagnostics
        .dedup_by_key(|entry| (entry.span_start, entry.span_end));
    probe.diagnostics
}

struct Probe<'s> {
    scoping: &'s Scoping,
    selected: HashSet<SymbolId>,
    module: bool,
    reason: &'static str,
    depth: usize,
    pattern_depth: Option<usize>,
    diagnostics: Vec<Diagnostic>,
}
impl Probe<'_> {
    fn report(&mut self, reason: &'static str, span: Span) {
        if reason == self.reason {
            self.diagnostics.push(Diagnostic {
                reason,
                span_start: span.start,
                span_end: span.end,
                message: None,
            });
        }
    }
    fn selected_pattern(&self, pattern: &BindingPattern<'_>) -> bool {
        struct Selection<'s> {
            selected: &'s HashSet<SymbolId>,
            found: bool,
        }
        impl<'a> Visit<'a> for Selection<'_> {
            fn visit_binding_identifier(&mut self, id: &BindingIdentifier<'a>) {
                self.found |= id
                    .symbol_id
                    .get()
                    .is_some_and(|id| self.selected.contains(&id));
            }
        }
        let mut selection = Selection {
            selected: &self.selected,
            found: false,
        };
        selection.visit_binding_pattern(pattern);
        selection.found
    }
}
impl<'a> Visit<'a> for Probe<'_> {
    fn visit_identifier_reference(&mut self, id: &IdentifierReference<'a>) {
        if id.name.starts_with("__weiv_") {
            self.report("reserved_identifier", id.span);
        }
        if id.name == "eval" {
            self.report("dynamic_eval", id.span);
        }
        if let Some(reference) = id
            .reference_id
            .get()
            .map(|id| self.scoping.get_reference(id))
        {
            if reference.is_write() {
                if let Some(symbol) = reference.symbol_id() {
                    let flags = self.scoping.symbol_flags(symbol);
                    if (self.selected.contains(&symbol) || (!self.module && flags.is_import()))
                        && (flags.is_const_variable() || flags.is_import())
                    {
                        self.report("const_assignment", id.span);
                    }
                }
            }
        }
    }
    fn visit_binding_identifier(&mut self, id: &BindingIdentifier<'a>) {
        if id.name.starts_with("__weiv_") {
            self.report("reserved_identifier", id.span);
        }
    }
    fn visit_variable_declaration(&mut self, declaration: &VariableDeclaration<'a>) {
        let selected = declaration
            .declarations
            .iter()
            .any(|declaration| self.selected_pattern(&declaration.id));
        if declaration.declare && (selected || !self.module) {
            self.report("ambient_declaration", declaration.span);
        }
        if selected
            && !matches!(
                declaration.kind,
                VariableDeclarationKind::Let | VariableDeclarationKind::Const
            )
        {
            self.report("declaration_kind", declaration.span);
        }
        walk::walk_variable_declaration(self, declaration);
    }
    fn visit_variable_declarator(&mut self, declaration: &VariableDeclarator<'a>) {
        let previous = self.pattern_depth;
        if !matches!(declaration.id, BindingPattern::BindingIdentifier(_))
            && self.selected_pattern(&declaration.id)
        {
            self.pattern_depth = Some(self.depth);
        }
        self.visit_binding_pattern(&declaration.id);
        self.pattern_depth = previous;
        if let Some(init) = &declaration.init {
            self.visit_expression(init);
        }
    }
    fn visit_function(&mut self, function: &Function<'a>, flags: ScopeFlags) {
        self.depth += 1;
        walk::walk_function(self, function, flags);
        self.depth -= 1;
    }
    fn visit_arrow_function_expression(&mut self, function: &ArrowFunctionExpression<'a>) {
        self.depth += 1;
        walk::walk_arrow_function_expression(self, function);
        self.depth -= 1;
    }
    fn visit_await_expression(&mut self, expression: &AwaitExpression<'a>) {
        if (!self.module && self.depth == 0) || self.pattern_depth == Some(self.depth) {
            self.report("top_level_await", expression.span);
        }
        walk::walk_await_expression(self, expression);
    }
    fn visit_for_of_statement(&mut self, statement: &ForOfStatement<'a>) {
        if statement.r#await && !self.module && self.depth == 0 {
            self.report("top_level_await", statement.span);
        }
        walk::walk_for_of_statement(self, statement);
    }
    fn visit_export_default_declaration(&mut self, declaration: &ExportDefaultDeclaration<'a>) {
        if !self.module {
            self.report("component_default_export", declaration.span);
        }
        walk::walk_export_default_declaration(self, declaration);
    }
}

#[cfg(test)]
mod tests {
    use super::inspect;

    #[test]
    fn original_write_spans_survive_declaration_extraction_and_shadowing() {
        let source = "const {count=class {static label=this.name}}={};function shadow(count){count++}count++;";
        for module in [false, true] {
            let entries = inspect(source, "source.ts", &["count".into()], module);
            assert_eq!(entries.len(), 1);
            assert_eq!(entries[0].reason, "const_assignment");
            assert_eq!(
                entries[0].span_start as usize,
                source.rfind("count++").unwrap()
            );
            assert_eq!(
                &source[entries[0].span_start as usize..entries[0].span_end as usize],
                "count"
            );
        }
    }

    #[test]
    fn declaration_spans_use_selected_symbols_and_success_has_no_diagnostics() {
        let source = "var count=0;function shadow(){var count=1;count++}";
        let entries = inspect(source, "source.ts", &["count".into()], false);
        assert_eq!(entries.len(), 1);
        assert_eq!(
            &source[entries[0].span_start as usize..entries[0].span_end as usize],
            "var count=0;"
        );
        assert!(inspect(
            "let count=0;function shadow(){const count=1;return count}",
            "source.ts",
            &["count".into()],
            false
        )
        .is_empty());
    }

    #[test]
    fn await_locations_preserve_the_component_and_module_boundary() {
        let input = "export let {count}=await Promise.resolve({count:1});";
        assert_eq!(
            inspect(input, "source.ts", &["count".into()], false).len(),
            1
        );
        assert!(inspect(input, "source.ts", &["count".into()], true).is_empty());
        let pattern = "export let {count=await Promise.resolve(1)}={};";
        let entries = inspect(pattern, "source.ts", &["count".into()], true);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].reason, "top_level_await");
        assert_eq!(
            &pattern[entries[0].span_start as usize..entries[0].span_end as usize],
            "await Promise.resolve(1)"
        );
    }
}
