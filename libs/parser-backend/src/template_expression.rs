use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::{walk, Visit};
use oxc_parser::Parser;
use oxc_semantic::{Scoping, SemanticBuilder};
use oxc_span::SourceType;
use std::collections::{BTreeMap, BTreeSet};

pub fn handler_kind(source: &str) -> u8 {
    fn reference(expression: &Expression<'_>) -> u8 {
        match expression.get_inner_expression() {
            Expression::Identifier(_)
            | Expression::StaticMemberExpression(_)
            | Expression::ComputedMemberExpression(_)
            | Expression::ArrowFunctionExpression(_)
            | Expression::FunctionExpression(_) => 1,
            Expression::ConditionalExpression(_) | Expression::LogicalExpression(_) => 2,
            Expression::SequenceExpression(sequence) => sequence
                .expressions
                .last()
                .map_or(0, |last| if reference(last) > 0 { 2 } else { 0 }),
            Expression::ChainExpression(chain) => match &chain.expression {
                ChainElement::CallExpression(_) => 0,
                ChainElement::TSNonNullExpression(value) => reference(&value.expression),
                _ => 1,
            },
            _ => 0,
        }
    }
    let allocator = Allocator::default();
    let wrapper = format!("({source});");
    let parsed = Parser::new(&allocator, &wrapper, SourceType::ts()).parse();
    if !parsed.errors.is_empty() {
        return 0;
    }
    match parsed.program.body.first() {
        Some(Statement::ExpressionStatement(statement)) => reference(&statement.expression),
        _ => 0,
    }
}

// Edit only unresolved references. Source spans preserve methods, defaults,
// precedence and callback bodies while semantic identities preserve shadowing.
pub fn rewrite(source: &str, names: &BTreeSet<String>, prefix: &str) -> Option<String> {
    let allocator = Allocator::default();
    let wrapper = format!("({source});");
    let parsed = Parser::new(&allocator, &wrapper, SourceType::ts()).parse();
    if !parsed.errors.is_empty() {
        return None;
    }
    let semantic = SemanticBuilder::new().build(&parsed.program);
    let scoping = semantic.semantic.into_scoping();
    let mut visitor = References {
        scoping: &scoping,
        names,
        prefix,
        edits: BTreeMap::new(),
    };
    visitor.visit_program(&parsed.program);
    let mut result = wrapper;
    for ((start, end), value) in visitor.edits.into_iter().rev() {
        result.replace_range(start..end, &value);
    }
    Some(result[1..result.len() - 2].to_string())
}

struct References<'s> {
    scoping: &'s Scoping,
    names: &'s BTreeSet<String>,
    prefix: &'s str,
    edits: BTreeMap<(usize, usize), String>,
}
impl References<'_> {
    fn selected(&self, id: &IdentifierReference<'_>) -> bool {
        self.names.contains(id.name.as_str())
            && id
                .reference_id
                .get()
                .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none())
    }
}
impl<'a> Visit<'a> for References<'_> {
    fn visit_identifier_reference(&mut self, id: &IdentifierReference<'a>) {
        if self.selected(id) {
            self.edits.insert(
                (id.span.start as usize, id.span.end as usize),
                format!("{}.{}", self.prefix, id.name),
            );
        }
    }
    fn visit_object_property(&mut self, property: &ObjectProperty<'a>) {
        if property.shorthand {
            if let Expression::Identifier(id) = &property.value {
                if self.selected(id) {
                    self.edits.insert(
                        (id.span.start as usize, id.span.end as usize),
                        format!("{}: {}.{}", id.name, self.prefix, id.name),
                    );
                    return;
                }
            }
        }
        walk::walk_object_property(self, property);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handlers_distinguish_references_selectors_and_evaluated_expressions() {
        for source in [
            "read",
            "holder.read",
            "holder[key]",
            "holder?.read",
            "event=>read(event)",
        ] {
            assert_eq!(handler_kind(source), 1, "{source}");
        }
        for source in [
            "enabled && read",
            "enabled ? first : second",
            "(count++, read)",
        ] {
            assert_eq!(handler_kind(source), 2, "{source}");
        }
        for source in [
            "read()",
            "read?.()",
            "callback=()=>count++",
            "count++",
            "delete state.item",
        ] {
            assert_eq!(handler_kind(source), 0, "{source}");
        }
    }
    #[test]
    fn callbacks_keep_local_names_and_rewrite_captured_shorthand() {
        let names = ["count", "rows"].map(String::from).into_iter().collect();
        let source = "rows.map(({count}) => { const local=count; return {count, local, next:()=>({rows})}; })";
        assert_eq!(rewrite(source, &names, "scope").unwrap(), "scope.rows.map(({count}) => { const local=count; return {count, local, next:()=>({rows: scope.rows})}; })");
        assert_eq!(
            rewrite("({read(){return {count};}})", &names, "scope").unwrap(),
            "({read(){return {count: scope.count};}})"
        );
    }
}
