//! Lexical provenance facts only. Parsing a module never claims managed/reactive
//! coverage; the build graph must supply that ownership separately.
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_ast_visit::{walk, Visit};
use oxc_parser::Parser;
use oxc_semantic::{ScopeFlags, ScopeId, Scoping, SemanticBuilder, SymbolId};
use oxc_span::{GetSpan, SourceType};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet, HashMap};

#[derive(Default, Serialize)]
pub struct ModuleState {
    pub ok: bool,
    pub managed: bool,
    pub source_path: String,
    pub imports: Vec<Import>,
    pub sources: Vec<ModuleSource>,
    pub opaque_dynamic_import: bool,
    pub opaque_dynamic_imports: Vec<SourceSpan>,
    pub bindings: Vec<Binding>,
    pub exports: Vec<Export>,
    pub root_writes: BTreeSet<String>,
    pub assignments: Vec<Assignment>,
    pub argument_flows: Vec<ArgumentFlow>,
    pub iterable_mutations: BTreeSet<String>,
    pub dynamic_access: bool,
    pub diagnostics: Vec<String>,
}
#[derive(Serialize)]
pub struct ModuleSource {
    pub source: String,
    pub dynamic: bool,
    pub span_start: u32,
    pub span_end: u32,
}
#[derive(Serialize)]
pub struct SourceSpan {
    pub span_start: u32,
    pub span_end: u32,
}
#[derive(Serialize)]
pub struct Import {
    pub local: String,
    pub imported: String,
    pub source: String,
}
#[derive(Serialize)]
pub struct Binding {
    pub name: String,
    pub declaration_kind: String,
    pub value_kind: String,
    pub alias: Option<String>,
    pub factory: Option<String>,
    pub reads: BTreeSet<String>,
    pub writes: BTreeSet<String>,
    pub globals: BTreeSet<String>,
    pub has_mutation: bool,
    pub retained_local_state: bool,
    pub retained_local_calls: BTreeSet<String>,
    pub result_projections: BTreeSet<String>,
    pub calls: BTreeSet<String>,
    pub call_counts: Vec<CallCount>,
    pub reference_counts: Vec<CallCount>,
    pub accesses: Vec<Access>,
    pub coercions: Vec<Coercion>,
    pub effects: Vec<CallEffect>,
    pub shape: ValueShape,
    pub span_start: u32,
    pub span_end: u32,
}
#[derive(Serialize)]
pub struct CallCount {
    pub name: String,
    pub count: usize,
}

#[derive(Clone, Serialize)]
pub struct Access {
    pub name: String,
    pub path: Option<String>,
    pub call: bool,
}

#[derive(Clone, Serialize)]
pub struct Coercion {
    pub name: String,
    pub path: Option<String>,
    pub hint: u8,
    pub native: Option<String>,
}

#[derive(Clone, Serialize)]
pub struct CallEffect {
    pub value: ValueShape,
    pub hint: u8,
    pub native: Option<String>,
    pub option: Option<Box<ValueShape>>,
}

#[derive(Clone, Default, Serialize)]
pub struct ValueShape {
    pub callee: Option<String>,
    pub callee_value: Option<Box<ValueShape>>,
    pub native_callee: bool,
    pub member_call: bool,
    pub string_value: Option<String>,
    pub lexical_this: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub effects: Vec<CallEffect>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub factory: Option<String>,
    pub parameter_index: Option<usize>,
    pub scope_id: Option<u32>,
    pub rest_parameter: bool,
    pub arguments_expanded: bool,
    pub truthy: Option<bool>,
    pub nullish: Option<bool>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub values: Vec<ValueShape>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub properties: Vec<ShapeProperty>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub returns: Vec<ValueShape>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub captured_locals: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub captured_shapes: Vec<ValueShape>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub captured_opaque_paths: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub invocation: Option<Box<ValueShape>>,
    pub async_result: bool,
    pub generator_result: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub accesses: Vec<Access>,
    pub coercions: Vec<Coercion>,
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub calls: BTreeSet<String>,
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub globals: BTreeSet<String>,
    pub has_mutation: bool,
    pub retained_local_state: bool,
    pub retained_local_calls: BTreeSet<String>,
    pub result_projections: BTreeSet<String>,
}
#[derive(Clone, Serialize)]
pub struct ShapeProperty {
    pub name: Option<String>,
    pub value: ValueShape,
}

#[derive(Serialize)]
pub struct ArgumentFlow {
    pub target: String,
    pub callee: String,
    pub spread: bool,
    pub indirect: bool,
    pub argument_index: usize,
}

#[derive(Serialize)]
pub struct Assignment {
    pub target: String,
    /// None denotes a root write; computed members set dynamic_path.
    pub path: Option<String>,
    pub dynamic_path: bool,
    pub operator: String,
    pub projected: bool,
    pub inputs: BTreeSet<String>,
    pub value: Binding,
}

#[derive(Serialize)]
pub struct Export {
    pub exported: String,
    pub local: Option<String>,
    pub source: Option<String>,
    pub imported: Option<String>,
    pub kind: String,
}

pub fn analyze(source: &str, path: &str) -> ModuleState {
    let allocator = Allocator::default();
    let parsed = Parser::new(
        &allocator,
        source,
        SourceType::from_path(path).unwrap_or(SourceType::ts()),
    )
    .parse();
    if !parsed.errors.is_empty() {
        return ModuleState {
            diagnostics: parsed.errors.iter().map(ToString::to_string).collect(),
            source_path: path.into(),
            ..Default::default()
        };
    }
    let semantic = SemanticBuilder::new()
        .with_check_syntax_error(true)
        .build(&parsed.program);
    if !semantic.errors.is_empty() {
        return ModuleState {
            source_path: path.into(),
            diagnostics: semantic.errors.iter().map(ToString::to_string).collect(),
            ..Default::default()
        };
    }
    let scoping = semantic.semantic.into_scoping();
    let mut result = ModuleState {
        ok: true,
        source_path: path.into(),
        ..Default::default()
    };
    let mut dynamic_sources = DynamicSources::default();
    dynamic_sources.visit_program(&parsed.program);
    result.opaque_dynamic_import = dynamic_sources.opaque;
    result.opaque_dynamic_imports = dynamic_sources.opaque_spans;
    result.sources = dynamic_sources.sources;

    let mut factories = HashMap::<SymbolId, String>::new();
    for statement in &parsed.program.body {
        let source = match statement {
            Statement::ImportDeclaration(import) => Some(&import.source),
            Statement::ExportNamedDeclaration(export) => export.source.as_ref(),
            Statement::ExportAllDeclaration(export) => Some(&export.source),
            _ => None,
        };
        if let Some(source) = source {
            result.sources.push(ModuleSource {
                source: source.value.to_string(),
                dynamic: false,
                span_start: source.span.start,
                span_end: source.span.end,
            });
        }
        if let Statement::ImportDeclaration(import) = statement {
            if import.import_kind == ImportOrExportKind::Type {
                continue;
            }
            if let Some(specifiers) = &import.specifiers {
                for specifier in specifiers {
                    let (local, imported) = match specifier {
                        ImportDeclarationSpecifier::ImportSpecifier(s)
                            if s.import_kind != ImportOrExportKind::Type =>
                        {
                            (&s.local, s.imported.name().to_string())
                        }
                        ImportDeclarationSpecifier::ImportDefaultSpecifier(s) => {
                            (&s.local, "default".into())
                        }
                        ImportDeclarationSpecifier::ImportNamespaceSpecifier(s) => {
                            (&s.local, "*".into())
                        }
                        _ => continue,
                    };
                    if import.source.value == "weiv:observable" {
                        if let Some(id) = local.symbol_id.get() {
                            factories.insert(id, imported.clone());
                        }
                    }
                    result.imports.push(Import {
                        local: local.name.to_string(),
                        imported,
                        source: import.source.value.to_string(),
                    });
                }
            }
        }
    }
    let mut module_references = References::new(&scoping, &factories);
    module_references.visit_program(&parsed.program);
    result.dynamic_access = module_references.globals.contains("eval");
    result.root_writes = module_references.writes;
    for statement in &parsed.program.body {
        match statement {
            Statement::ExportNamedDeclaration(export)
                if export.export_kind != ImportOrExportKind::Type =>
            {
                if let Some(declaration) = &export.declaration {
                    declaration_facts(declaration, true, &scoping, &factories, &mut result);
                }
                for specifier in &export.specifiers {
                    if specifier.export_kind == ImportOrExportKind::Type {
                        continue;
                    }
                    result.exports.push(Export {
                        exported: specifier.exported.name().to_string(),
                        local: if export.source.is_none() {
                            Some(specifier.local.name().to_string())
                        } else {
                            None
                        },
                        source: export.source.as_ref().map(|s| s.value.to_string()),
                        imported: export
                            .source
                            .as_ref()
                            .map(|_| specifier.local.name().to_string()),
                        kind: if export.source.is_some() {
                            "reexport"
                        } else {
                            "local"
                        }
                        .into(),
                    });
                }
            }
            Statement::ExportAllDeclaration(export)
                if export.export_kind != ImportOrExportKind::Type =>
            {
                result.exports.push(Export {
                    exported: export
                        .exported
                        .as_ref()
                        .map_or("*".into(), |n| n.name().to_string()),
                    local: None,
                    source: Some(export.source.value.to_string()),
                    imported: Some("*".into()),
                    kind: if export.exported.is_some() {
                        "namespace_reexport"
                    } else {
                        "star"
                    }
                    .into(),
                })
            }
            Statement::ExportDefaultDeclaration(export) => {
                let local = match &export.declaration {
                    ExportDefaultDeclarationKind::FunctionDeclaration(function) => {
                        let name = function
                            .id
                            .as_ref()
                            .map_or("<default>".into(), |id| id.name.to_string());
                        let mut reads = References::new(&scoping, &factories);
                        reads.visit_function(function, ScopeFlags::Function);
                        result.bindings.push(reads.binding(
                            name.clone(),
                            if function.body.is_some() && !function.declare {
                                "function"
                            } else {
                                "ambient"
                            },
                            if function.body.is_some() && !function.declare {
                                "function"
                            } else {
                                "unknown"
                            },
                            None,
                            None,
                            function.span,
                        ));
                        if let Some(body) = &function.body {
                            result.bindings.last_mut().unwrap().shape = ValueShape {
                                kind: "function".into(),
                                scope_id: function.scope_id.get().map(|scope| scope.index() as u32),
                                returns: return_shapes(
                                    body,
                                    &function.params,
                                    false,
                                    &scoping,
                                    &factories,
                                    0,
                                ),
                                invocation: Some(resolved_invocation_shape(
                                    body,
                                    &function.params,
                                    function.scope_id.get(),
                                    &scoping,
                                    &factories,
                                    0,
                                )),
                                async_result: function.r#async,
                                generator_result: function.generator,
                                ..Default::default()
                            };
                        }
                        name
                    }
                    other => {
                        if let Some(expression) = other.as_expression() {
                            let mut refs = References::new(&scoping, &factories);
                            refs.visit_expression(expression);
                            let (kind, alias, factory) =
                                value_kind(expression, &scoping, &factories);
                            result.bindings.push(refs.binding(
                                "<default>".into(),
                                "const",
                                kind,
                                alias,
                                factory,
                                expression.span(),
                            ));
                            result.bindings.last_mut().unwrap().shape =
                                value_shape(expression, &scoping, &factories, 0);
                        } else {
                            result
                                .bindings
                                .push(References::new(&scoping, &factories).binding(
                                    "<default>".into(),
                                    "unknown",
                                    "unknown",
                                    None,
                                    None,
                                    other.span(),
                                ));
                        }
                        "<default>".into()
                    }
                };
                result.exports.push(Export {
                    exported: "default".into(),
                    local: Some(local),
                    source: None,
                    imported: None,
                    kind: "local".into(),
                });
            }
            _ => {
                if let Some(declaration) = statement.as_declaration() {
                    declaration_facts(declaration, false, &scoping, &factories, &mut result);
                }
            }
        }
    }
    let mut argument_aliases = ArgumentAliases {
        scoping: &scoping,
        values: HashMap::new(),
    };
    argument_aliases.visit_program(&parsed.program);
    let mut incoming = Incoming {
        argument_aliases: argument_aliases.values,
        scoping: &scoping,
        factories: &factories,
        assignments: Vec::new(),
        argument_flows: Vec::new(),
        iterable_mutations: BTreeSet::new(),
    };
    incoming.visit_program(&parsed.program);
    result.assignments = incoming.assignments;
    result.argument_flows = incoming.argument_flows;
    result.iterable_mutations = incoming.iterable_mutations;
    for binding in &mut result.bindings {
        identify_receiver_scopes(&mut binding.shape, None, 0);
    }
    result.sources.sort_by_key(|source| source.span_start);
    result
}

#[derive(Default)]
struct DynamicSources {
    sources: Vec<ModuleSource>,
    opaque: bool,
    opaque_spans: Vec<SourceSpan>,
}
impl<'a> Visit<'a> for DynamicSources {
    fn visit_import_expression(&mut self, expression: &ImportExpression<'a>) {
        match expression.source.get_inner_expression() {
            Expression::StringLiteral(source) => self.sources.push(ModuleSource {
                source: source.value.to_string(),
                dynamic: true,
                span_start: source.span.start,
                span_end: source.span.end,
            }),
            _ => {
                self.opaque = true;
                self.opaque_spans.push(SourceSpan {
                    span_start: expression.span.start,
                    span_end: expression.span.end,
                });
            }
        }
        walk::walk_import_expression(self, expression);
    }
}

fn declaration_facts(
    declaration: &Declaration<'_>,
    exported: bool,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    result: &mut ModuleState,
) {
    let start = result.bindings.len();
    match declaration {
        Declaration::VariableDeclaration(declaration) => {
            for declarator in &declaration.declarations {
                let mut names = Vec::new();
                super::collect_binding_names(&declarator.id, &mut names);
                let mut shapes = HashMap::new();
                if let Some(init) = &declarator.init {
                    bind_shapes(
                        &declarator.id,
                        value_shape(init, scoping, factories, 0),
                        &mut shapes,
                        scoping,
                        factories,
                        0,
                        true,
                    );
                }
                for (name, start, _) in names {
                    let mut refs = References::new(scoping, factories);
                    refs.visit_variable_declarator(declarator);
                    let (kind, alias, factory) =
                        if matches!(&declarator.id, BindingPattern::BindingIdentifier(_)) {
                            declarator
                                .init
                                .as_ref()
                                .map_or(("uninitialized", None, None), |e| {
                                    value_kind(e, scoping, factories)
                                })
                        } else {
                            ("destructured", None, None)
                        };
                    let declaration_kind = match declaration.kind {
                        VariableDeclarationKind::Const => "const",
                        VariableDeclarationKind::Let => "let",
                        _ => "var",
                    };
                    result.bindings.push(refs.binding(
                        name,
                        if declaration.declare {
                            "ambient"
                        } else {
                            declaration_kind
                        },
                        kind,
                        alias,
                        factory,
                        declarator.span,
                    ));
                    result.bindings.last_mut().unwrap().shape =
                        shapes.remove(&start.to_string()).unwrap_or_default();
                }
            }
        }
        Declaration::FunctionDeclaration(function) => {
            if let Some(id) = &function.id {
                let mut refs = References::new(scoping, factories);
                refs.visit_function(function, ScopeFlags::Function);
                result.bindings.push(refs.binding(
                    id.name.to_string(),
                    if function.body.is_some() && !function.declare {
                        "function"
                    } else {
                        "ambient"
                    },
                    if function.body.is_some() && !function.declare {
                        "function"
                    } else {
                        "unknown"
                    },
                    None,
                    None,
                    function.span,
                ));
                if let Some(body) = &function.body {
                    result.bindings.last_mut().unwrap().shape = ValueShape {
                        kind: "function".into(),
                        scope_id: function.scope_id.get().map(|scope| scope.index() as u32),
                        returns: return_shapes(
                            body,
                            &function.params,
                            false,
                            scoping,
                            factories,
                            0,
                        ),
                        invocation: Some(resolved_invocation_shape(
                            body,
                            &function.params,
                            function.scope_id.get(),
                            scoping,
                            factories,
                            0,
                        )),
                        async_result: function.r#async,
                        generator_result: function.generator,
                        ..Default::default()
                    };
                }
            }
        }
        Declaration::ClassDeclaration(class) => {
            if let Some(id) = &class.id {
                let mut refs = References::new(scoping, factories);
                refs.visit_class(class);
                result.bindings.push(refs.binding(
                    id.name.to_string(),
                    "class",
                    "class",
                    None,
                    None,
                    class.span,
                ));
            }
        }
        _ => {}
    }
    if exported {
        for binding in &result.bindings[start..] {
            result.exports.push(Export {
                exported: binding.name.clone(),
                local: Some(binding.name.clone()),
                source: None,
                imported: None,
                kind: "local".into(),
            });
        }
    }
}

fn value_kind(
    expression: &Expression<'_>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
) -> (&'static str, Option<String>, Option<String>) {
    match expression.get_inner_expression() {
        Expression::Identifier(id) => {
            if module_reference(id, scoping) {
                ("alias", Some(id.name.to_string()), None)
            } else if id
                .reference_id
                .get()
                .is_some_and(|id| scoping.get_reference(id).symbol_id().is_none())
            {
                (
                    if matches!(id.name.as_str(), "undefined" | "NaN" | "Infinity") {
                        "primitive"
                    } else {
                        "global"
                    },
                    None,
                    None,
                )
            } else {
                ("input", None, None)
            }
        }
        Expression::StringLiteral(_)
        | Expression::NumericLiteral(_)
        | Expression::BooleanLiteral(_)
        | Expression::NullLiteral(_)
        | Expression::BigIntLiteral(_) => ("primitive", None, None),
        Expression::ObjectExpression(_) => ("object", None, None),
        Expression::ArrayExpression(_) => ("array", None, None),
        Expression::ClassExpression(_) => ("class", None, None),
        Expression::ArrowFunctionExpression(_) | Expression::FunctionExpression(_) => {
            ("function", None, None)
        }
        Expression::CallExpression(call) => {
            let (id, member) = match call.callee.get_inner_expression() {
                Expression::Identifier(id) => (Some(id.as_ref()), None),
                Expression::StaticMemberExpression(member) => (
                    match member.object.get_inner_expression() {
                        Expression::Identifier(id) => Some(id.as_ref()),
                        _ => None,
                    },
                    Some(member.property.name.as_str()),
                ),
                Expression::ComputedMemberExpression(member) => (
                    match member.object.get_inner_expression() {
                        Expression::Identifier(id) => Some(id.as_ref()),
                        _ => None,
                    },
                    static_property(&member.expression),
                ),
                _ => (None, None),
            };
            let factory = id
                .and_then(|id| id.reference_id.get())
                .and_then(|id| scoping.get_reference(id).symbol_id())
                .and_then(|id| factories.get(&id));
            let known = match factory.map(String::as_str) {
                Some("*") => member,
                Some(name) if member.is_none() => Some(name),
                _ => None,
            };
            let kind = match known {
                Some("observable") => "observable",
                Some("snapshot") => "snapshot",
                _ => "call",
            };
            (
                kind,
                None,
                id.filter(|id| module_reference(id, scoping))
                    .map(|id| match member {
                        Some(member) => format!("{}.{}", id.name, member),
                        None => id.name.to_string(),
                    }),
            )
        }
        _ => ("unknown", None, None),
    }
}

fn identify_receiver_scopes(shape: &mut ValueShape, inherited: Option<u32>, depth: usize) {
    if depth >= 64 {
        return;
    }
    let owner = if shape.kind == "function" && !shape.lexical_this {
        shape.scope_id
    } else {
        inherited
    };
    if matches!(shape.kind.as_str(), "receiver" | "effects") {
        shape.scope_id = owner;
    }
    if let Some(callee) = &mut shape.callee_value {
        identify_receiver_scopes(callee, owner, depth + 1);
    }
    if let Some(invocation) = &mut shape.invocation {
        identify_receiver_scopes(invocation, owner, depth + 1);
    }
    for value in &mut shape.values {
        identify_receiver_scopes(value, owner, depth + 1);
    }
    for value in &mut shape.returns {
        identify_receiver_scopes(value, owner, depth + 1);
    }
    for value in &mut shape.captured_shapes {
        identify_receiver_scopes(value, owner, depth + 1);
    }
    for property in &mut shape.properties {
        identify_receiver_scopes(&mut property.value, owner, depth + 1);
    }
    for effect in &mut shape.effects {
        identify_receiver_scopes(&mut effect.value, owner, depth + 1);
        if let Some(option) = &mut effect.option {
            identify_receiver_scopes(option, owner, depth + 1);
        }
    }
}

fn receiver_root(expression: &Expression<'_>) -> bool {
    match expression.get_inner_expression() {
        Expression::ThisExpression(_) => true,
        Expression::StaticMemberExpression(member) => receiver_root(&member.object),
        Expression::ComputedMemberExpression(member) => receiver_root(&member.object),
        _ => false,
    }
}

fn callee_shape(
    expression: &Expression<'_>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
) -> Option<Box<ValueShape>> {
    if depth >= 32 {
        return None;
    }
    let shape = match expression.get_inner_expression() {
        Expression::StaticMemberExpression(member) => ValueShape {
            kind: "projection".into(),
            path: Some(member.property.name.to_string()),
            values: vec![value_shape(&member.object, scoping, factories, depth + 1)],
            ..Default::default()
        },
        Expression::ComputedMemberExpression(member) => {
            if let Some(key) = static_property(&member.expression) {
                ValueShape {
                    kind: "projection".into(),
                    path: Some(key.into()),
                    values: vec![value_shape(&member.object, scoping, factories, depth + 1)],
                    ..Default::default()
                }
            } else {
                ValueShape {
                    kind: "computed_projection".into(),
                    values: vec![
                        value_shape(&member.object, scoping, factories, depth + 1),
                        value_shape(&member.expression, scoping, factories, depth + 1),
                    ],
                    ..Default::default()
                }
            }
        }
        Expression::Identifier(id)
            if !module_reference(id, scoping)
                && id
                    .reference_id
                    .get()
                    .is_some_and(|id| scoping.get_reference(id).symbol_id().is_some()) =>
        {
            value_shape(expression, scoping, factories, depth + 1)
        }
        _ => return None,
    };
    Some(Box::new(shape))
}

fn value_shape(
    expression: &Expression<'_>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
) -> ValueShape {
    if depth >= 32 {
        return ValueShape::default();
    }
    let mut shape = ValueShape::default();
    match expression.get_inner_expression() {
        Expression::ObjectExpression(object) => {
            shape.kind = "record".into();
            for property in &object.properties {
                match property {
                    ObjectPropertyKind::ObjectProperty(property)
                        if property.kind == PropertyKind::Init =>
                    {
                        let name = match &property.key {
                            PropertyKey::StaticIdentifier(id) if !property.computed => {
                                Some(id.name.to_string())
                            }
                            PropertyKey::StringLiteral(key) => Some(key.value.to_string()),
                            _ => None,
                        };
                        shape.properties.push(ShapeProperty {
                            name,
                            value: value_shape(&property.value, scoping, factories, depth + 1),
                        });
                    }
                    _ => shape.properties.push(ShapeProperty {
                        name: None,
                        value: ValueShape::default(),
                    }),
                }
            }
        }
        Expression::ArrayExpression(array) => {
            shape.kind = "array".into();
            for element in &array.elements {
                shape.values.push(element.as_expression().map_or_else(
                    || {
                        if matches!(element, ArrayExpressionElement::Elision(_)) {
                            ValueShape {
                                kind: "undefined".into(),
                                ..Default::default()
                            }
                        } else {
                            ValueShape::default()
                        }
                    },
                    |element| value_shape(element, scoping, factories, depth + 1),
                ));
            }
        }
        Expression::FunctionExpression(_) | Expression::ArrowFunctionExpression(_) => {
            shape.kind = "function".into();
            let mut refs = References::new(scoping, factories);
            refs.visit_expression(expression);
            let scope = match expression.get_inner_expression() {
                Expression::ArrowFunctionExpression(f) => f.scope_id.get(),
                Expression::FunctionExpression(f) => f.scope_id.get(),
                _ => None,
            };
            if let Some(scope) = scope {
                shape.captured_locals = refs
                    .local_references
                    .iter()
                    .filter(|(symbol, _)| {
                        !scoping
                            .scope_ancestors(scoping.symbol_scope_id(*symbol))
                            .any(|ancestor| ancestor == scope)
                    })
                    .map(|(symbol, _)| scoping.symbol_span(*symbol).start.to_string())
                    .collect::<BTreeSet<_>>()
                    .into_iter()
                    .collect();
            }
            for (symbol, path) in &refs.local_member_paths {
                if !shape
                    .captured_locals
                    .contains(&scoping.symbol_span(*symbol).start.to_string())
                {
                    continue;
                }
                let opaque = path.split('.').any(|part| {
                    matches!(
                        part,
                        "[computed]"
                            | "constructor"
                            | "__proto__"
                            | "__defineGetter__"
                            | "__defineSetter__"
                            | "__lookupGetter__"
                            | "__lookupSetter__"
                            | "toString"
                            | "toLocaleString"
                            | "valueOf"
                            | "hasOwnProperty"
                            | "propertyIsEnumerable"
                            | "isPrototypeOf"
                            | "at"
                            | "concat"
                            | "copyWithin"
                            | "entries"
                            | "every"
                            | "fill"
                            | "filter"
                            | "find"
                            | "findIndex"
                            | "findLast"
                            | "findLastIndex"
                            | "flat"
                            | "flatMap"
                            | "forEach"
                            | "includes"
                            | "indexOf"
                            | "join"
                            | "keys"
                            | "lastIndexOf"
                            | "map"
                            | "pop"
                            | "push"
                            | "reduce"
                            | "reduceRight"
                            | "reverse"
                            | "shift"
                            | "slice"
                            | "some"
                            | "sort"
                            | "splice"
                            | "toReversed"
                            | "toSorted"
                            | "toSpliced"
                            | "unshift"
                            | "values"
                            | "with"
                    )
                });
                if opaque {
                    shape
                        .captured_opaque_paths
                        .push(format!("{}.{path}", scoping.symbol_name(*symbol)));
                }
            }
            shape.retained_local_state = refs.retains_local_state();
            shape.retained_local_calls = refs.retained_local_calls();
            shape.effects = refs.effects;
            shape.coercions = refs
                .coercions
                .into_iter()
                .map(|((name, path, native), hint)| Coercion {
                    name,
                    path,
                    hint,
                    native,
                })
                .collect();
            shape.accesses = refs
                .accesses
                .into_iter()
                .map(|((name, path), call)| Access { name, path, call })
                .collect();
            shape.calls = refs.calls;
            shape.globals = refs.globals;
            shape.has_mutation = refs.has_mutation;
            shape.result_projections = refs.result_projections;
            match expression.get_inner_expression() {
                Expression::ArrowFunctionExpression(function) => {
                    shape.lexical_this = true;
                    shape.scope_id = function.scope_id.get().map(|scope| scope.index() as u32);
                    shape.async_result = function.r#async;
                    shape.invocation = Some(resolved_invocation_shape(
                        &function.body,
                        &function.params,
                        function.scope_id.get(),
                        scoping,
                        factories,
                        depth + 1,
                    ));
                    shape.returns = return_shapes(
                        &function.body,
                        &function.params,
                        function.expression,
                        scoping,
                        factories,
                        depth + 1,
                    )
                }
                Expression::FunctionExpression(function) => {
                    shape.scope_id = function.scope_id.get().map(|scope| scope.index() as u32);
                    shape.async_result = function.r#async;
                    shape.generator_result = function.generator;
                    if let Some(body) = &function.body {
                        shape.invocation = Some(resolved_invocation_shape(
                            body,
                            &function.params,
                            function.scope_id.get(),
                            scoping,
                            factories,
                            depth + 1,
                        ));
                        shape.returns = return_shapes(
                            body,
                            &function.params,
                            false,
                            scoping,
                            factories,
                            depth + 1,
                        )
                    }
                }
                _ => {}
            }
        }
        Expression::ClassExpression(_) => shape.kind = "class".into(),
        Expression::CallExpression(call) => {
            shape.kind = "call".into();
            shape.factory = value_kind(expression, scoping, factories).2;
            shape.callee_value = callee_shape(&call.callee, scoping, factories, depth + 1);
            shape.member_call = matches!(
                call.callee.get_inner_expression(),
                Expression::StaticMemberExpression(_) | Expression::ComputedMemberExpression(_)
            );
            if let Some((id, _, _)) = write_path(&call.callee) {
                if !module_reference(id, scoping)
                    && id
                        .reference_id
                        .get()
                        .is_some_and(|id| scoping.get_reference(id).symbol_id().is_some())
                {
                    shape.name = Some(
                        static_access(&call.callee)
                            .map(|(id, path)| {
                                if path.is_empty() {
                                    id.name.to_string()
                                } else {
                                    format!("{}.{path}", id.name)
                                }
                            })
                            .unwrap_or_else(|| "<dynamic>".into()),
                    );
                }
            }
            if let Some((id, path)) = static_access(&call.callee) {
                let global = id
                    .reference_id
                    .get()
                    .is_some_and(|id| scoping.get_reference(id).symbol_id().is_none());
                if global || module_reference(id, scoping) {
                    shape.callee = Some(format!(
                        "{}{}{}",
                        id.name,
                        if path.is_empty() { "" } else { "." },
                        path
                    ));
                    shape.native_callee = global;
                }
                if global
                    && id.name == "Object"
                    && matches!(
                        path.as_str(),
                        "assign" | "freeze" | "seal" | "preventExtensions"
                    )
                {
                    shape.factory = Some(format!("global:Object.{path}"));
                }
            }
            if primitive_conversion(expression, scoping) {
                shape.kind = "primitive".into();
            }
            shape.arguments_expanded = call
                .arguments
                .iter()
                .any(|argument| matches!(argument, Argument::SpreadElement(_)));
            for argument in &call.arguments {
                shape.values.push(
                    argument
                        .as_expression()
                        .map_or_else(ValueShape::default, |value| {
                            value_shape(value, scoping, factories, depth + 1)
                        }),
                );
            }
        }
        Expression::ThisExpression(_) => shape.kind = "receiver".into(),
        Expression::Identifier(_)
        | Expression::StaticMemberExpression(_)
        | Expression::ComputedMemberExpression(_) => {
            if let Some((id, path)) = static_access(expression) {
                if id.name == "undefined"
                    && path.is_empty()
                    && id
                        .reference_id
                        .get()
                        .is_some_and(|id| scoping.get_reference(id).symbol_id().is_none())
                {
                    shape.kind = "undefined".into();
                } else if module_reference(id, scoping) {
                    shape.kind = "reference".into();
                    shape.name = Some(id.name.to_string());
                    shape.path = if path.is_empty() { None } else { Some(path) };
                } else if let Some(symbol) = id
                    .reference_id
                    .get()
                    .and_then(|id| scoping.get_reference(id).symbol_id())
                {
                    shape.kind = "local_reference".into();
                    shape.name = Some(scoping.symbol_span(symbol).start.to_string());
                    shape.path = if path.is_empty() { None } else { Some(path) };
                } else {
                    shape.kind = "reference".into();
                    shape.name = Some(id.name.to_string());
                    shape.path = if path.is_empty() { None } else { Some(path) };
                }
            } else {
                match expression.get_inner_expression() {
                    Expression::StaticMemberExpression(member) => {
                        shape = projected_shape(
                            value_shape(&member.object, scoping, factories, depth + 1),
                            member.property.name.as_str(),
                        )
                    }
                    Expression::ComputedMemberExpression(member) => {
                        shape = if let Some(key) = static_property(&member.expression) {
                            projected_shape(
                                value_shape(&member.object, scoping, factories, depth + 1),
                                key,
                            )
                        } else {
                            ValueShape {
                                kind: "computed_projection".into(),
                                values: vec![
                                    value_shape(&member.object, scoping, factories, depth + 1),
                                    value_shape(&member.expression, scoping, factories, depth + 1),
                                ],
                                ..Default::default()
                            }
                        };
                    }
                    _ => {}
                }
            }
        }
        Expression::LogicalExpression(value) => {
            shape.kind = "logical".into();
            shape.name = Some(value.operator.as_str().into());
            shape.values = vec![
                value_shape(&value.left, scoping, factories, depth + 1),
                value_shape(&value.right, scoping, factories, depth + 1),
            ];
        }
        Expression::ConditionalExpression(value) => {
            shape.kind = "conditional".into();
            shape.values = vec![
                value_shape(&value.test, scoping, factories, depth + 1),
                value_shape(&value.consequent, scoping, factories, depth + 1),
                value_shape(&value.alternate, scoping, factories, depth + 1),
            ];
        }
        Expression::SequenceExpression(value) => {
            shape.kind = "sequence".into();
            shape.values = value
                .expressions
                .last()
                .map(|value| vec![value_shape(value, scoping, factories, depth + 1)])
                .unwrap_or_default();
        }
        Expression::StringLiteral(value) => {
            shape.string_value = Some(value.value.to_string());
            shape.kind = "primitive".into();
            shape.truthy = Some(!value.value.is_empty());
        }
        Expression::NumericLiteral(value) => {
            shape.kind = "primitive".into();
            shape.truthy = Some(value.value != 0.0 && !value.value.is_nan());
        }
        Expression::BooleanLiteral(value) => {
            shape.kind = "primitive".into();
            shape.truthy = Some(value.value);
        }
        Expression::NullLiteral(_) => {
            shape.kind = "primitive".into();
            shape.truthy = Some(false);
            shape.nullish = Some(true);
        }
        Expression::UnaryExpression(value) if value.operator.as_str() == "void" => {
            shape.kind = "undefined".into();
            shape.truthy = Some(false);
            shape.nullish = Some(true);
        }
        Expression::BigIntLiteral(_)
        | Expression::TemplateLiteral(_)
        | Expression::BinaryExpression(_)
        | Expression::UnaryExpression(_) => shape.kind = "primitive".into(),
        _ => {}
    }
    shape
}

fn projected_shape(source: ValueShape, path: &str) -> ValueShape {
    if source.kind == "record" {
        for property in source.properties.iter().rev() {
            match &property.name {
                Some(name) if name == path => return property.value.clone(),
                None => break,
                _ => {}
            }
        }
    }
    if source.kind == "array" {
        if let Ok(index) = path.parse::<usize>() {
            if let Some(value) = source.values.get(index) {
                return value.clone();
            }
        }
    }
    ValueShape {
        kind: "projection".into(),
        path: Some(path.into()),
        values: vec![source],
        ..Default::default()
    }
}
fn identify_parameter_scope(shape: &mut ValueShape, scope: u32, depth: usize) {
    if depth >= 32 {
        return;
    }
    if shape.kind == "parameter" && shape.scope_id.is_none() {
        shape.scope_id = Some(scope);
    }
    for value in &mut shape.values {
        identify_parameter_scope(value, scope, depth + 1);
    }
}
fn bind_return_shape(
    pattern: &BindingPattern<'_>,
    source: ValueShape,
    locals: &mut HashMap<String, ValueShape>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
) {
    bind_shapes(pattern, source, locals, scoping, factories, depth, false);
}
fn bind_shapes(
    pattern: &BindingPattern<'_>,
    mut source: ValueShape,
    locals: &mut HashMap<String, ValueShape>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
    preserve_mutated: bool,
) {
    if depth >= 32 {
        return;
    }
    match pattern {
        BindingPattern::BindingIdentifier(id) => {
            if let Some(symbol) = id.symbol_id.get() {
                identify_parameter_scope(
                    &mut source,
                    scoping.symbol_scope_id(symbol).index() as u32,
                    0,
                );
                locals.insert(
                    scoping.symbol_span(symbol).start.to_string(),
                    if !preserve_mutated && scoping.symbol_is_mutated(symbol) {
                        ValueShape::default()
                    } else {
                        source
                    },
                );
            }
        }
        BindingPattern::ObjectPattern(object) => {
            for property in &object.properties {
                let key = match &property.key {
                    PropertyKey::StaticIdentifier(id) if !property.computed => {
                        Some(id.name.as_str())
                    }
                    PropertyKey::StringLiteral(key) if !key.value.contains('.') => {
                        Some(key.value.as_str())
                    }
                    _ => None,
                };
                let mut value = key
                    .map(|key| projected_shape(source.clone(), key))
                    .unwrap_or_default();
                if preserve_mutated && value.kind == "projection" {
                    value.kind = "declaration_projection".into();
                }
                bind_shapes(
                    &property.value,
                    value,
                    locals,
                    scoping,
                    factories,
                    depth + 1,
                    preserve_mutated,
                );
            }
            if let Some(rest) = &object.rest {
                let keys: Option<Vec<String>> = object
                    .properties
                    .iter()
                    .map(|property| match &property.key {
                        PropertyKey::StaticIdentifier(id) if !property.computed => {
                            Some(id.name.to_string())
                        }
                        PropertyKey::StringLiteral(key) => Some(key.value.to_string()),
                        _ => None,
                    })
                    .collect();
                let rest_shape = if !preserve_mutated {
                    ValueShape::default()
                } else if source.kind == "record"
                    && keys.is_some()
                    && source
                        .properties
                        .iter()
                        .all(|property| property.name.is_some())
                {
                    let keys = keys.unwrap();
                    ValueShape {
                        kind: "record".into(),
                        properties: source
                            .properties
                            .iter()
                            .filter(|property| !keys.contains(property.name.as_ref().unwrap()))
                            .cloned()
                            .collect(),
                        ..Default::default()
                    }
                } else {
                    ValueShape {
                        kind: "destructure_rest".into(),
                        values: vec![source.clone()],
                        ..Default::default()
                    }
                };
                bind_shapes(
                    &rest.argument,
                    rest_shape,
                    locals,
                    scoping,
                    factories,
                    depth + 1,
                    preserve_mutated,
                );
            }
        }
        BindingPattern::ArrayPattern(array) => {
            for (index, pattern) in array.elements.iter().enumerate() {
                if let Some(pattern) = pattern {
                    let value = if preserve_mutated {
                        ValueShape {
                            kind: "declaration_iteration".into(),
                            path: Some(index.to_string()),
                            values: vec![source.clone()],
                            ..Default::default()
                        }
                    } else {
                        projected_shape(source.clone(), &index.to_string())
                    };
                    bind_shapes(
                        pattern,
                        value,
                        locals,
                        scoping,
                        factories,
                        depth + 1,
                        preserve_mutated,
                    );
                }
            }
            if let Some(rest) = &array.rest {
                let rest_shape = if !preserve_mutated {
                    ValueShape::default()
                } else if source.kind == "array" && !source.arguments_expanded {
                    ValueShape {
                        kind: "array".into(),
                        values: source
                            .values
                            .iter()
                            .skip(array.elements.len())
                            .cloned()
                            .collect(),
                        ..Default::default()
                    }
                } else {
                    ValueShape {
                        kind: "declaration_array_rest".into(),
                        values: vec![source.clone()],
                        ..Default::default()
                    }
                };
                bind_shapes(
                    &rest.argument,
                    rest_shape,
                    locals,
                    scoping,
                    factories,
                    depth + 1,
                    preserve_mutated,
                );
            }
        }
        BindingPattern::AssignmentPattern(default) => {
            let value = if source.kind == "undefined" {
                value_shape(&default.right, scoping, factories, depth + 1)
            } else if matches!(
                source.kind.as_str(),
                "primitive" | "record" | "array" | "function"
            ) {
                source
            } else {
                ValueShape {
                    kind: "default".into(),
                    values: vec![
                        source,
                        value_shape(&default.right, scoping, factories, depth + 1),
                    ],
                    ..Default::default()
                }
            };
            bind_shapes(
                &default.left,
                value,
                locals,
                scoping,
                factories,
                depth + 1,
                preserve_mutated,
            );
        }
    }
}

// Return provenance is lexical, not an invocation or ownership guarantee.
// Nested callable bodies provide their own returns and do not become outer ones.
struct ReturnShapes<'s> {
    scoping: &'s Scoping,
    factories: &'s HashMap<SymbolId, String>,
    locals: HashMap<String, ValueShape>,
    returns: Vec<ValueShape>,
    depth: usize,
    collect_returns: bool,
}
impl<'a> Visit<'a> for ReturnShapes<'_> {
    fn visit_function(&mut self, _: &Function<'a>, _: ScopeFlags) {}
    fn visit_arrow_function_expression(&mut self, _: &ArrowFunctionExpression<'a>) {}
    fn visit_return_statement(&mut self, statement: &ReturnStatement<'a>) {
        if !self.collect_returns {
            return;
        }
        self.returns.push(
            statement
                .argument
                .as_ref()
                .map(|value| value_shape(value, self.scoping, self.factories, self.depth + 1))
                .unwrap_or_else(|| ValueShape {
                    kind: "primitive".into(),
                    ..Default::default()
                }),
        );
        // Initializers in nested expressions are separate lexical functions.
    }
    fn visit_variable_declarator(&mut self, declaration: &VariableDeclarator<'a>) {
        let shape = declaration
            .init
            .as_ref()
            .map(|value| {
                if primitive_conversion(value, self.scoping) {
                    ValueShape {
                        kind: "primitive".into(),
                        ..Default::default()
                    }
                } else {
                    value_shape(value, self.scoping, self.factories, self.depth + 1)
                }
            })
            .unwrap_or_default();
        bind_return_shape(
            &declaration.id,
            shape,
            &mut self.locals,
            self.scoping,
            self.factories,
            self.depth + 1,
        );
    }
}
struct ReturnResolution {
    seen: BTreeSet<String>,
    remaining: usize,
}
fn resolve_return_locals(
    mut shape: ValueShape,
    locals: &HashMap<String, ValueShape>,
    depth: usize,
    resolution: &mut ReturnResolution,
) -> ValueShape {
    if depth >= 32 || resolution.remaining == 0 {
        return ValueShape::default();
    }
    resolution.remaining -= 1;
    if shape.kind == "local_reference" {
        let Some(value) = shape.name.as_ref().and_then(|name| locals.get(name)) else {
            // An enclosing callable may still own this captured reference.
            return shape;
        };
        let name = shape.name.as_ref().unwrap();
        if !resolution.seen.insert(name.clone()) {
            return ValueShape::default();
        }
        let value = resolve_return_locals(value.clone(), locals, depth + 1, resolution);
        resolution.seen.remove(name);
        return if shape.path.is_some() {
            ValueShape {
                kind: "projection".into(),
                path: shape.path,
                values: vec![value],
                ..Default::default()
            }
        } else {
            value
        };
    }
    if let Some(callee) = shape.callee_value.take() {
        shape.callee_value = Some(Box::new(resolve_return_locals(
            *callee,
            locals,
            depth + 1,
            resolution,
        )));
    }
    if let Some(effects) = shape.invocation.take() {
        shape.invocation = Some(Box::new(resolve_return_locals(
            *effects,
            locals,
            depth + 1,
            resolution,
        )));
    }
    let captures = std::mem::take(&mut shape.captured_locals);
    for name in captures {
        if let Some(value) = locals.get(&name) {
            if !resolution.seen.insert(name.clone()) {
                shape.captured_shapes.push(ValueShape::default());
                continue;
            }
            let value = resolve_return_locals(value.clone(), locals, depth + 1, resolution);
            resolution.seen.remove(&name);
            if value.kind != "primitive" {
                shape.captured_shapes.push(value);
            }
        } else {
            shape.captured_locals.push(name);
        }
    }
    for effect in &mut shape.effects {
        effect.value = resolve_return_locals(
            std::mem::take(&mut effect.value),
            locals,
            depth + 1,
            resolution,
        );
        if let Some(option) = effect.option.take() {
            effect.option = Some(Box::new(resolve_return_locals(
                *option,
                locals,
                depth + 1,
                resolution,
            )));
        }
    }
    shape.values = shape
        .values
        .into_iter()
        .map(|value| resolve_return_locals(value, locals, depth + 1, resolution))
        .collect();
    shape.returns = shape
        .returns
        .into_iter()
        .map(|value| resolve_return_locals(value, locals, depth + 1, resolution))
        .collect();
    shape.captured_shapes = shape
        .captured_shapes
        .into_iter()
        .map(|value| resolve_return_locals(value, locals, depth + 1, resolution))
        .collect();
    for property in &mut shape.properties {
        property.value = resolve_return_locals(
            std::mem::take(&mut property.value),
            locals,
            depth + 1,
            resolution,
        );
    }
    shape
}
fn invocation_shape(
    body: &FunctionBody<'_>,
    scope: Option<ScopeId>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
) -> Box<ValueShape> {
    let mut refs = References::new(scoping, factories);
    refs.skip_nested_functions = true;
    refs.function_depth = 1;
    refs.visit_function_body(body);
    let captured_locals = scope
        .map(|scope| {
            refs.local_references
                .iter()
                .filter(|(symbol, _)| {
                    !scoping
                        .scope_ancestors(scoping.symbol_scope_id(*symbol))
                        .any(|ancestor| ancestor == scope)
                })
                .map(|(symbol, _)| scoping.symbol_span(*symbol).start.to_string())
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect()
        })
        .unwrap_or_default();
    let retained_local_state = refs.retains_local_state();
    let retained_local_calls = refs.retained_local_calls();
    Box::new(ValueShape {
        kind: "effects".into(),
        captured_locals,
        retained_local_state,
        retained_local_calls,
        result_projections: refs.result_projections,
        effects: refs.effects,
        coercions: refs
            .coercions
            .into_iter()
            .map(|((name, path, native), hint)| Coercion {
                name,
                path,
                hint,
                native,
            })
            .collect(),
        accesses: refs
            .accesses
            .into_iter()
            .map(|((name, path), call)| Access { name, path, call })
            .collect(),
        calls: refs.calls,
        globals: refs.globals,
        has_mutation: refs.has_mutation,
        ..Default::default()
    })
}

fn collect_function_shapes<'s>(
    body: &FunctionBody<'_>,
    params: &FormalParameters<'_>,
    expression: bool,
    scoping: &'s Scoping,
    factories: &'s HashMap<SymbolId, String>,
    depth: usize,
    collect_returns: bool,
) -> ReturnShapes<'s> {
    let mut collector = ReturnShapes {
        scoping,
        factories,
        locals: HashMap::new(),
        returns: Vec::new(),
        depth,
        collect_returns,
    };
    if depth >= 32 {
        return collector;
    }
    for (index, parameter) in params.items.iter().enumerate() {
        let shape = ValueShape {
            kind: "parameter".into(),
            parameter_index: Some(index),
            values: parameter
                .initializer
                .as_ref()
                .map(|value| vec![value_shape(value, scoping, factories, depth + 1)])
                .unwrap_or_default(),
            ..Default::default()
        };
        bind_return_shape(
            &parameter.pattern,
            shape,
            &mut collector.locals,
            scoping,
            factories,
            depth + 1,
        );
    }
    if let Some(rest) = &params.rest {
        bind_return_shape(
            &rest.rest.argument,
            ValueShape {
                kind: "parameter".into(),
                parameter_index: Some(params.items.len()),
                rest_parameter: true,
                ..Default::default()
            },
            &mut collector.locals,
            scoping,
            factories,
            depth + 1,
        );
    }
    if expression {
        if collect_returns {
            if let Some(Statement::ExpressionStatement(statement)) = body.statements.first() {
                collector.returns.push(value_shape(
                    &statement.expression,
                    scoping,
                    factories,
                    depth + 1,
                ));
            }
        }
    } else {
        collector.visit_function_body(body);
    }
    collector
}

fn resolved_invocation_shape(
    body: &FunctionBody<'_>,
    params: &FormalParameters<'_>,
    scope: Option<ScopeId>,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
) -> Box<ValueShape> {
    let collector = collect_function_shapes(body, params, false, scoping, factories, depth, false);
    Box::new(resolve_return_locals(
        *invocation_shape(body, scope, scoping, factories),
        &collector.locals,
        0,
        &mut ReturnResolution {
            seen: BTreeSet::new(),
            remaining: 4096,
        },
    ))
}

fn return_shapes(
    body: &FunctionBody<'_>,
    params: &FormalParameters<'_>,
    expression: bool,
    scoping: &Scoping,
    factories: &HashMap<SymbolId, String>,
    depth: usize,
) -> Vec<ValueShape> {
    let collector =
        collect_function_shapes(body, params, expression, scoping, factories, depth, true);
    collector
        .returns
        .into_iter()
        .map(|value| {
            resolve_return_locals(
                value,
                &collector.locals,
                0,
                &mut ReturnResolution {
                    seen: BTreeSet::new(),
                    remaining: 4096,
                },
            )
        })
        .collect()
}

fn primitive_conversion(expression: &Expression<'_>, scoping: &Scoping) -> bool {
    if let Expression::CallExpression(call) = expression.get_inner_expression() {
        if let Expression::Identifier(id) = call.callee.get_inner_expression() {
            return id
                .reference_id
                .get()
                .is_some_and(|id| scoping.get_reference(id).symbol_id().is_none())
                && matches!(
                    id.name.as_str(),
                    "String"
                        | "Number"
                        | "Boolean"
                        | "BigInt"
                        | "Symbol"
                        | "parseInt"
                        | "parseFloat"
                        | "isFinite"
                        | "isNaN"
                );
        }
    }
    false
}

fn module_reference(id: &IdentifierReference<'_>, scoping: &Scoping) -> bool {
    id.reference_id
        .get()
        .and_then(|id| scoping.get_reference(id).symbol_id())
        .is_some_and(|symbol| scoping.symbol_scope_id(symbol) == scoping.root_scope_id())
}

struct Incoming<'s> {
    scoping: &'s Scoping,
    argument_aliases: HashMap<SymbolId, BTreeSet<SymbolId>>,
    factories: &'s HashMap<SymbolId, String>,
    assignments: Vec<Assignment>,
    argument_flows: Vec<ArgumentFlow>,
    iterable_mutations: BTreeSet<String>,
}

#[derive(Clone)]
struct WriteTarget {
    name: String,
    path: Option<String>,
    dynamic: bool,
}

fn write_path<'s, 'a>(
    expression: &'s Expression<'a>,
) -> Option<(&'s IdentifierReference<'a>, Option<String>, bool)> {
    match expression.get_inner_expression() {
        Expression::Identifier(id) => Some((id, None, false)),
        Expression::StaticMemberExpression(member) => {
            let (id, path, dynamic) = write_path(&member.object)?;
            Some((
                id,
                Some(append_path(path, member.property.name.as_str())),
                dynamic,
            ))
        }
        Expression::ComputedMemberExpression(member) => {
            let (id, path, _) = write_path(&member.object)?;
            Some((id, Some(append_path(path, "[computed]")), true))
        }
        _ => None,
    }
}

fn append_path(path: Option<String>, property: &str) -> String {
    match path {
        Some(path) => format!("{path}.{property}"),
        None => property.into(),
    }
}

struct WriteTargets<'s> {
    scoping: &'s Scoping,
    targets: Vec<WriteTarget>,
}
impl WriteTargets<'_> {
    fn add(&mut self, id: &IdentifierReference<'_>, path: Option<String>, dynamic: bool) {
        if module_reference(id, self.scoping) {
            self.targets.push(WriteTarget {
                name: id.name.to_string(),
                path,
                dynamic,
            });
        }
    }
}
impl<'a> Visit<'a> for WriteTargets<'_> {
    fn visit_assignment_target(&mut self, target: &AssignmentTarget<'a>) {
        let found = match target {
            AssignmentTarget::AssignmentTargetIdentifier(id) => Some((id.as_ref(), None, false)),
            AssignmentTarget::StaticMemberExpression(member) => {
                write_path(&member.object).map(|(id, path, dynamic)| {
                    (
                        id,
                        Some(append_path(path, member.property.name.as_str())),
                        dynamic,
                    )
                })
            }
            AssignmentTarget::ComputedMemberExpression(member) => write_path(&member.object)
                .map(|(id, path, _)| (id, Some(append_path(path, "[computed]")), true)),
            AssignmentTarget::TSAsExpression(wrapper) => write_path(&wrapper.expression),
            AssignmentTarget::TSSatisfiesExpression(wrapper) => write_path(&wrapper.expression),
            AssignmentTarget::TSNonNullExpression(wrapper) => write_path(&wrapper.expression),
            AssignmentTarget::TSTypeAssertion(wrapper) => write_path(&wrapper.expression),
            _ => None,
        };
        if let Some((id, path, dynamic)) = found {
            self.add(id, path, dynamic);
        } else {
            walk::walk_assignment_target(self, target);
        }
    }
    fn visit_assignment_target_with_default(&mut self, target: &AssignmentTargetWithDefault<'a>) {
        self.visit_assignment_target(&target.binding);
    }
    fn visit_assignment_target_property_identifier(
        &mut self,
        target: &AssignmentTargetPropertyIdentifier<'a>,
    ) {
        self.add(&target.binding, None, false);
    }
}

fn write_targets(target: &AssignmentTarget<'_>, scoping: &Scoping) -> Vec<WriteTarget> {
    let mut collector = WriteTargets {
        scoping,
        targets: Vec::new(),
    };
    collector.visit_assignment_target(target);
    collector.targets
}

impl Incoming<'_> {
    fn record_alias_destination(
        &mut self,
        id: &IdentifierReference<'_>,
        path: Option<String>,
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        let Some(symbol) = id
            .reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
        else {
            return;
        };
        let mut roots = BTreeSet::new();
        self.argument_roots(symbol, &mut BTreeSet::new(), &mut roots);
        for name in roots {
            if module_reference(id, self.scoping) && name == id.name.as_str() {
                continue;
            }
            let first = self.assignments.len();
            self.record(
                &[WriteTarget {
                    name,
                    path: path.clone(),
                    dynamic: true,
                }],
                rhs,
                operator,
                span,
            );
            for assignment in &mut self.assignments[first..] {
                assignment.projected = true;
            }
        }
    }
    fn record_alias_member(
        &mut self,
        target: &AssignmentTarget<'_>,
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        match target {
            AssignmentTarget::StaticMemberExpression(member) => {
                if let Some((id, path, _)) = write_path(&member.object) {
                    self.record_alias_destination(
                        id,
                        Some(append_path(path, member.property.name.as_str())),
                        rhs,
                        operator,
                        span,
                    );
                }
            }
            AssignmentTarget::ComputedMemberExpression(member) => {
                if let Some((id, path, _)) = write_path(&member.object) {
                    self.record_alias_destination(
                        id,
                        Some(append_path(path, "[computed]")),
                        rhs,
                        operator,
                        span,
                    );
                }
            }
            AssignmentTarget::TSAsExpression(wrapper) => {
                self.record_alias_expression(&wrapper.expression, rhs, operator, span)
            }
            AssignmentTarget::TSSatisfiesExpression(wrapper) => {
                self.record_alias_expression(&wrapper.expression, rhs, operator, span)
            }
            AssignmentTarget::TSNonNullExpression(wrapper) => {
                self.record_alias_expression(&wrapper.expression, rhs, operator, span)
            }
            AssignmentTarget::TSTypeAssertion(wrapper) => {
                self.record_alias_expression(&wrapper.expression, rhs, operator, span)
            }
            _ => {}
        }
    }
    fn record_alias_expression(
        &mut self,
        expression: &Expression<'_>,
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        if let Some((id, path, _)) = write_path(expression) {
            if path.is_some() {
                self.record_alias_destination(id, path, rhs, operator, span);
            }
        }
    }
    fn record_alias_writes<'a>(
        &mut self,
        target: &AssignmentTarget<'a>,
        rhs: &Expression<'a>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        AliasWrites {
            incoming: self,
            rhs,
            operator,
            span,
        }
        .visit_assignment_target(target);
    }

    fn argument_roots(
        &self,
        symbol: SymbolId,
        seen: &mut BTreeSet<SymbolId>,
        roots: &mut BTreeSet<String>,
    ) {
        let mut pending = vec![symbol];
        while let Some(symbol) = pending.pop() {
            if !seen.insert(symbol) {
                continue;
            }
            if self.scoping.symbol_scope_id(symbol) == self.scoping.root_scope_id() {
                roots.insert(self.scoping.symbol_name(symbol).to_string());
            }
            if let Some(values) = self.argument_aliases.get(&symbol) {
                pending.extend(values.iter().copied());
            }
        }
    }

    fn record_property(
        &mut self,
        destination: &Expression<'_>,
        key: Option<&str>,
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        if let Some((id, path, dynamic)) = write_path(destination) {
            self.record_alias_destination(id, path.clone(), rhs, operator, span);
            if module_reference(id, self.scoping) {
                self.record(
                    &[WriteTarget {
                        name: id.name.to_string(),
                        path: Some(append_path(path, key.unwrap_or("[computed]"))),
                        dynamic: dynamic || key.is_none(),
                    }],
                    rhs,
                    operator,
                    span,
                );
            }
        }
    }
    fn record_destination(
        &mut self,
        destination: &Expression<'_>,
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        if let Some((id, path, dynamic)) = write_path(destination) {
            self.record_alias_destination(id, path.clone(), rhs, operator, span);
            if module_reference(id, self.scoping) {
                self.record(
                    &[WriteTarget {
                        name: id.name.to_string(),
                        path,
                        dynamic,
                    }],
                    rhs,
                    operator,
                    span,
                );
            }
        }
    }
    fn record(
        &mut self,
        targets: &[WriteTarget],
        rhs: &Expression<'_>,
        operator: &str,
        span: oxc_span::Span,
    ) {
        for target in targets {
            let mut refs = References::new(self.scoping, self.factories);
            refs.input_span = Some(rhs.span());
            // A for-in target receives a primitive key, not the enumerated
            // object's value. Defaults are recorded separately below.
            if operator != "for-in" {
                refs.visit_expression(rhs);
            }
            let inputs = std::mem::take(&mut refs.inputs);
            let (kind, alias, factory) = if operator == "for-in" {
                ("primitive", None, None)
            } else {
                value_kind(rhs, self.scoping, self.factories)
            };
            self.assignments.push(Assignment {
                target: target.name.clone(),
                path: target.path.clone(),
                dynamic_path: target.dynamic,
                operator: operator.into(),
                projected: false,
                inputs,
                value: refs.binding(
                    target.name.clone(),
                    "assignment",
                    kind,
                    alias,
                    factory,
                    span,
                ),
            });
            if operator != "for-in" {
                self.assignments.last_mut().unwrap().value.shape =
                    value_shape(rhs, self.scoping, self.factories, 0);
            }
        }
    }
}

// Traverse target patterns without treating computed keys, default RHS values,
// or alias rebinding as member mutations. The main Incoming walk handles effects
// inside those expressions independently with their actual source expressions.
struct AliasWrites<'v, 's, 'a> {
    incoming: &'v mut Incoming<'s>,
    rhs: &'v Expression<'a>,
    operator: &'v str,
    span: oxc_span::Span,
}
impl<'a> Visit<'a> for AliasWrites<'_, '_, 'a> {
    fn visit_expression(&mut self, _: &Expression<'a>) {}
    fn visit_assignment_target(&mut self, target: &AssignmentTarget<'a>) {
        self.incoming
            .record_alias_member(target, self.rhs, self.operator, self.span);
        match target {
            AssignmentTarget::ArrayAssignmentTarget(_)
            | AssignmentTarget::ObjectAssignmentTarget(_) => {
                walk::walk_assignment_target(self, target)
            }
            _ => {}
        }
    }
    fn visit_assignment_target_with_default(&mut self, target: &AssignmentTargetWithDefault<'a>) {
        self.visit_assignment_target(&target.binding);
    }
}

// Defaults have independent value provenance. Merging them into an observable
// RHS would let that RHS's explicit contract incorrectly hide a raw default.
struct WriteDefaults<'v, 's> {
    incoming: &'v mut Incoming<'s>,
}
impl<'a> Visit<'a> for WriteDefaults<'_, '_> {
    fn visit_assignment_target_with_default(&mut self, target: &AssignmentTargetWithDefault<'a>) {
        self.incoming
            .record_alias_writes(&target.binding, &target.init, "default", target.span);
        let targets = write_targets(&target.binding, self.incoming.scoping);
        self.incoming
            .record(&targets, &target.init, "default", target.span);
        self.visit_assignment_target(&target.binding);
    }
    fn visit_assignment_target_property_identifier(
        &mut self,
        target: &AssignmentTargetPropertyIdentifier<'a>,
    ) {
        if let Some(init) = &target.init {
            if module_reference(&target.binding, self.incoming.scoping) {
                self.incoming.record(
                    &[WriteTarget {
                        name: target.binding.name.to_string(),
                        path: None,
                        dynamic: false,
                    }],
                    init,
                    "default",
                    target.span,
                );
            }
        }
    }
}

impl<'a> Visit<'a> for Incoming<'_> {
    fn visit_call_expression(&mut self, call: &CallExpression<'a>) {
        // Passing tracked data to a helper is a potential incoming mutation
        // boundary even when no assignment names that data syntactically.
        let callee = static_access(&call.callee)
            .map(|(id, path)| {
                let global = id
                    .reference_id
                    .get()
                    .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none());
                format!(
                    "{}{}{}{}",
                    if global { "global:" } else { "" },
                    id.name,
                    if path.is_empty() { "" } else { "." },
                    path
                )
            })
            .unwrap_or_else(|| "<dynamic>".into());
        for (argument_index, argument) in call.arguments.iter().enumerate() {
            if let Some(value) = argument_value(argument) {
                let direct = write_path(value)
                    .filter(|(id, _, _)| module_reference(id, self.scoping))
                    .map(|(id, _, _)| id.name.as_str());
                let mut roots = BTreeSet::new();
                let mut symbols = BTreeSet::new();
                argument_symbols(value, self.scoping, &mut symbols);
                let mut seen = BTreeSet::new();
                for symbol in symbols {
                    self.argument_roots(symbol, &mut seen, &mut roots);
                }
                for target in roots {
                    self.argument_flows.push(ArgumentFlow {
                        indirect: direct != Some(target.as_str()),
                        argument_index,
                        target,
                        callee: callee.clone(),
                        spread: matches!(argument, Argument::SpreadElement(_)),
                    });
                }
            }
        }

        let member = match call.callee.get_inner_expression() {
            Expression::StaticMemberExpression(member) => {
                Some((&member.object, member.property.name.as_str()))
            }
            Expression::ComputedMemberExpression(member) => {
                static_property(&member.expression).map(|name| (&member.object, name))
            }
            _ => None,
        };
        if let Some((object, method)) = member {
            if matches!(
                method,
                "push"
                    | "pop"
                    | "shift"
                    | "unshift"
                    | "splice"
                    | "sort"
                    | "reverse"
                    | "fill"
                    | "copyWithin"
            ) {
                let mut symbols = BTreeSet::new();
                argument_symbols(object, self.scoping, &mut symbols);
                let mut roots = BTreeSet::new();
                let mut seen = BTreeSet::new();
                for symbol in symbols {
                    self.argument_roots(symbol, &mut seen, &mut roots);
                }
                self.iterable_mutations.extend(roots);
            }
            let global = match object.get_inner_expression() {
                Expression::Identifier(id)
                    if id
                        .reference_id
                        .get()
                        .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none()) =>
                {
                    Some(id.name.as_str())
                }
                _ => None,
            };
            let argument =
                |index: usize| call.arguments.get(index).and_then(Argument::as_expression);
            if global == Some("Object") && method == "assign" {
                if let Some(destination) = argument(0) {
                    for source in call.arguments.iter().skip(1) {
                        if let Some(source) = argument_value(source) {
                            self.record_destination(
                                destination,
                                source,
                                "Object.assign",
                                call.span,
                            );
                        }
                    }
                }
            } else if matches!(global, Some("Object" | "Reflect")) && method == "defineProperty" {
                if let (Some(destination), Some(descriptor)) = (argument(0), argument(2)) {
                    if let Some(value) = descriptor_value(descriptor) {
                        self.record_property(
                            destination,
                            argument(1).and_then(static_property),
                            value,
                            if global == Some("Object") {
                                "Object.defineProperty"
                            } else {
                                "Reflect.defineProperty"
                            },
                            call.span,
                        );
                    }
                }
            } else if global == Some("Object") && method == "defineProperties" {
                if let (Some(destination), Some(descriptors)) = (argument(0), argument(1)) {
                    if let Expression::ObjectExpression(map) = descriptors.get_inner_expression() {
                        for descriptor in &map.properties {
                            let value = match descriptor {
                                ObjectPropertyKind::ObjectProperty(property)
                                    if property.kind == PropertyKind::Init =>
                                {
                                    descriptor_value(&property.value)
                                }
                                _ => Some(descriptors),
                            };
                            if let Some(value) = value {
                                let key = match descriptor {
                                    ObjectPropertyKind::ObjectProperty(property) => match &property
                                        .key
                                    {
                                        PropertyKey::StaticIdentifier(id) if !property.computed => {
                                            Some(id.name.as_str())
                                        }
                                        PropertyKey::StringLiteral(key)
                                            if !key.value.contains('.') =>
                                        {
                                            Some(key.value.as_str())
                                        }
                                        _ => None,
                                    },
                                    _ => None,
                                };
                                self.record_property(
                                    destination,
                                    key,
                                    value,
                                    "Object.defineProperties",
                                    call.span,
                                );
                            }
                        }
                    } else {
                        self.record_destination(
                            destination,
                            descriptors,
                            "Object.defineProperties",
                            call.span,
                        );
                    }
                }
            } else if global == Some("Reflect") && method == "set" {
                if let (Some(destination), Some(value)) =
                    (argument(3).or_else(|| argument(0)), argument(2))
                {
                    self.record_property(
                        destination,
                        argument(1).and_then(static_property),
                        value,
                        "Reflect.set",
                        call.span,
                    );
                }
            } else if matches!(method, "push" | "unshift" | "splice" | "fill") {
                for (index, value) in call.arguments.iter().enumerate() {
                    if method == "fill" && index != 0 {
                        continue;
                    }
                    if method == "splice"
                        && index < 2
                        && !matches!(value, Argument::SpreadElement(_))
                    {
                        continue;
                    }
                    if let Some(value) = argument_value(value) {
                        let first = self.assignments.len();
                        self.record_destination(object, value, method, call.span);
                        if matches!(&call.arguments[index], Argument::SpreadElement(_)) {
                            for assignment in &mut self.assignments[first..] {
                                assignment.projected = true;
                            }
                        }
                    }
                }
            }
        }
        walk::walk_call_expression(self, call);
    }
    fn visit_assignment_expression(&mut self, expression: &AssignmentExpression<'a>) {
        self.record_alias_writes(
            &expression.left,
            &expression.right,
            expression.operator.as_str(),
            expression.span,
        );
        let targets = write_targets(&expression.left, self.scoping);
        let first = self.assignments.len();
        self.record(
            &targets,
            &expression.right,
            expression.operator.as_str(),
            expression.span,
        );
        if matches!(
            &expression.left,
            AssignmentTarget::ArrayAssignmentTarget(_)
                | AssignmentTarget::ObjectAssignmentTarget(_)
        ) {
            for assignment in &mut self.assignments[first..] {
                assignment.projected = true;
            }
        }
        WriteDefaults { incoming: self }.visit_assignment_target(&expression.left);
        walk::walk_assignment_expression(self, expression);
    }
    fn visit_for_of_statement(&mut self, statement: &ForOfStatement<'a>) {
        if let Some(target) = statement.left.as_assignment_target() {
            self.record_alias_writes(target, &statement.right, "for-of", statement.span);
            let targets = write_targets(target, self.scoping);
            self.record(&targets, &statement.right, "for-of", statement.span);
            for assignment in self.assignments.iter_mut().rev().take(targets.len()) {
                assignment.projected = true;
            }
            WriteDefaults { incoming: self }.visit_assignment_target(target);
        }
        walk::walk_for_of_statement(self, statement);
    }
    fn visit_for_in_statement(&mut self, statement: &ForInStatement<'a>) {
        if let Some(target) = statement.left.as_assignment_target() {
            self.record_alias_writes(target, &statement.right, "for-in", statement.span);
            let targets = write_targets(target, self.scoping);
            self.record(&targets, &statement.right, "for-in", statement.span);
            WriteDefaults { incoming: self }.visit_assignment_target(target);
        }
        walk::walk_for_in_statement(self, statement);
    }
}

// A conservative union across local/root alias declarations and reassignments.
// This prepass also handles aliases declared after the consuming closure.
struct ArgumentAliases<'s> {
    scoping: &'s Scoping,
    values: HashMap<SymbolId, BTreeSet<SymbolId>>,
}
struct AliasBindings {
    symbols: Vec<SymbolId>,
}
impl<'a> Visit<'a> for AliasBindings {
    fn visit_binding_identifier(&mut self, id: &BindingIdentifier<'a>) {
        if let Some(symbol) = id.symbol_id.get() {
            self.symbols.push(symbol);
        }
    }
}
impl<'a> Visit<'a> for ArgumentAliases<'_> {
    fn visit_variable_declarator(&mut self, declaration: &VariableDeclarator<'a>) {
        if let Some(init) = &declaration.init {
            let mut roots = BTreeSet::new();
            argument_symbols(init, self.scoping, &mut roots);
            let mut bindings = AliasBindings {
                symbols: Vec::new(),
            };
            bindings.visit_binding_pattern(&declaration.id);
            for symbol in bindings.symbols {
                self.values
                    .entry(symbol)
                    .or_default()
                    .extend(roots.iter().copied());
            }
        }
        walk::walk_variable_declarator(self, declaration);
    }
    fn visit_assignment_expression(&mut self, assignment: &AssignmentExpression<'a>) {
        if let AssignmentTarget::AssignmentTargetIdentifier(id) = &assignment.left {
            if let Some(symbol) = id
                .reference_id
                .get()
                .and_then(|id| self.scoping.get_reference(id).symbol_id())
            {
                let mut roots = BTreeSet::new();
                argument_symbols(&assignment.right, self.scoping, &mut roots);
                self.values.entry(symbol).or_default().extend(roots);
            }
        }
        walk::walk_assignment_expression(self, assignment);
    }
}

// Only expression forms that pass references through are traversed. Function
// bodies, arithmetic, computed keys and call implementations are separate facts.
fn argument_symbols(
    expression: &Expression<'_>,
    scoping: &Scoping,
    roots: &mut BTreeSet<SymbolId>,
) {
    if let Some((id, _, _)) = write_path(expression) {
        if let Some(symbol) = id
            .reference_id
            .get()
            .and_then(|id| scoping.get_reference(id).symbol_id())
        {
            roots.insert(symbol);
        }
        return;
    }
    match expression.get_inner_expression() {
        Expression::ArrayExpression(array) => {
            for element in &array.elements {
                match element {
                    ArrayExpressionElement::SpreadElement(spread) => {
                        argument_symbols(&spread.argument, scoping, roots)
                    }
                    _ => {
                        if let Some(value) = element.as_expression() {
                            argument_symbols(value, scoping, roots)
                        }
                    }
                }
            }
        }
        Expression::ObjectExpression(object) => {
            for property in &object.properties {
                match property {
                    ObjectPropertyKind::ObjectProperty(property)
                        if property.kind == PropertyKind::Init =>
                    {
                        argument_symbols(&property.value, scoping, roots)
                    }
                    ObjectPropertyKind::SpreadProperty(spread) => {
                        argument_symbols(&spread.argument, scoping, roots)
                    }
                    _ => {}
                }
            }
        }
        Expression::ConditionalExpression(value) => {
            argument_symbols(&value.consequent, scoping, roots);
            argument_symbols(&value.alternate, scoping, roots);
        }
        Expression::LogicalExpression(value) => {
            argument_symbols(&value.left, scoping, roots);
            argument_symbols(&value.right, scoping, roots);
        }
        Expression::SequenceExpression(value) => {
            if let Some(last) = value.expressions.last() {
                argument_symbols(last, scoping, roots)
            }
        }
        _ => {}
    }
}

fn argument_value<'s, 'a>(argument: &'s Argument<'a>) -> Option<&'s Expression<'a>> {
    match argument {
        Argument::SpreadElement(spread) => Some(&spread.argument),
        _ => argument.as_expression(),
    }
}

// Only descriptor.value transfers data. Descriptor flags do not introduce raw
// state, and a known observable in value keeps its explicit runtime contract.
fn descriptor_value<'s, 'a>(expression: &'s Expression<'a>) -> Option<&'s Expression<'a>> {
    if let Expression::ObjectExpression(object) = expression.get_inner_expression() {
        let mut value = None;
        for property in &object.properties {
            let ObjectPropertyKind::ObjectProperty(property) = property else {
                return Some(expression);
            };
            let name = match &property.key {
                PropertyKey::StaticIdentifier(id) => Some(id.name.as_str()),
                PropertyKey::StringLiteral(key) => Some(key.value.as_str()),
                _ => None,
            };
            if property.kind != PropertyKind::Init || name.is_none() {
                return Some(expression);
            }
            if name == Some("value") {
                value = Some(&property.value);
            }
        }
        value
    } else {
        Some(expression)
    }
}

struct References<'s> {
    scoping: &'s Scoping,
    factories: &'s HashMap<SymbolId, String>,
    reads: BTreeSet<String>,
    writes: BTreeSet<String>,
    globals: BTreeSet<String>,
    has_mutation: bool,
    retained_local_state: bool,
    local_references: Vec<(SymbolId, usize)>,
    local_member_paths: BTreeSet<(SymbolId, String)>,
    result_projections: BTreeSet<String>,
    local_objects: HashMap<SymbolId, usize>,
    local_call_values: HashMap<SymbolId, (usize, String)>,
    projected_parameters: HashMap<SymbolId, (String, Option<String>)>,
    function_depth: usize,
    skip_nested_functions: bool,
    eager_functions: BTreeSet<u32>,
    calls: BTreeSet<String>,
    call_counts: BTreeMap<String, usize>,
    reference_counts: BTreeMap<String, usize>,
    accesses: BTreeMap<(String, Option<String>), bool>,
    coercions: BTreeMap<(String, Option<String>, Option<String>), u8>,
    effects: Vec<CallEffect>,
    native_coercion: Option<String>,
    coercing: u8,
    in_member_root: bool,
    input_span: Option<oxc_span::Span>,
    inputs: BTreeSet<String>,
}
impl<'s> References<'s> {
    fn record_effect(&mut self, effect: CallEffect) {
        // Nested callable construction does not execute that callable's body.
        // Its own invocation shape records those effects in its lexical scope.
        if self.function_depth <= 1 {
            self.effects.push(effect);
        }
    }
    fn record_expanded_native(
        &mut self,
        call: &CallExpression<'_>,
        native: &str,
        operation: &str,
        hint: u8,
    ) {
        let values = call
            .arguments
            .iter()
            .map(|argument| match argument {
                Argument::SpreadElement(spread) => ValueShape {
                    kind: "spread".into(),
                    values: vec![value_shape(
                        &spread.argument,
                        self.scoping,
                        self.factories,
                        0,
                    )],
                    ..Default::default()
                },
                _ => argument
                    .as_expression()
                    .map_or_else(ValueShape::default, |value| {
                        value_shape(value, self.scoping, self.factories, 0)
                    }),
            })
            .collect();
        self.record_effect(CallEffect {
            value: ValueShape {
                kind: "native_arguments".into(),
                callee: Some(operation.into()),
                values,
                ..Default::default()
            },
            hint,
            native: Some(native.into()),
            option: None,
        });
    }
    fn record_coercion(&mut self, value: &Expression<'_>, hint: u8) {
        if let Some((id, path)) = static_access(value)
            .or_else(|| write_path(value).map(|(id, path, _)| (id, path.unwrap_or_default())))
        {
            let previous = self.coercing;
            self.coercing = hint;
            self.record_root(id, if path.is_empty() { None } else { Some(path) }, false);
            self.coercing = previous;
        } else {
            self.record_effect(CallEffect {
                value: value_shape(value, self.scoping, self.factories, 0),
                hint,
                native: self.native_coercion.clone(),
                option: None,
            });
        }
    }
    fn retained_local_calls(&self) -> BTreeSet<String> {
        self.local_references
            .iter()
            .filter_map(|(symbol, depth)| {
                self.local_call_values
                    .get(symbol)
                    .filter(|(allocation, _)| depth > allocation)
                    .map(|(_, factory)| factory.clone())
            })
            .collect()
    }
    fn retains_local_state(&self) -> bool {
        self.retained_local_state
            || self.local_references.iter().any(|(symbol, depth)| {
                self.local_objects
                    .get(symbol)
                    .is_some_and(|allocation| depth > allocation)
            })
    }
    fn result_projection(&mut self, object: &Expression<'_>, member: &str) {
        let Expression::CallExpression(call) = object.get_inner_expression() else {
            return;
        };
        let callee = static_access(&call.callee);
        if let Some((root, path)) = &callee {
            let global = root
                .reference_id
                .get()
                .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none());
            if global
                && (matches!(
                    root.name.as_str(),
                    "Math" | "JSON" | "String" | "Number" | "Boolean" | "BigInt"
                ) || (root.name == "Object"
                    && matches!(
                        path.as_str(),
                        "keys" | "values" | "entries" | "fromEntries" | "is" | "hasOwn"
                    )))
            {
                return;
            }
        }
        let source = callee
            .map(|(root, path)| {
                format!(
                    "{}{}{}",
                    root.name,
                    if path.is_empty() { "" } else { "." },
                    path
                )
            })
            .unwrap_or_else(|| "<dynamic>".into());
        self.result_projections
            .insert(format!("{source}().{member}"));
    }
    fn record_root(&mut self, id: &IdentifierReference<'_>, path: Option<String>, call: bool) {
        if let Some(symbol) = id
            .reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
        {
            if self.scoping.symbol_scope_id(symbol) != self.scoping.root_scope_id() {
                if let Some(path) = &path {
                    self.local_member_paths.insert((symbol, path.clone()));
                }
            }
        }
        if let Some((name, prefix)) = id
            .reference_id
            .get()
            .and_then(|id| self.scoping.get_reference(id).symbol_id())
            .and_then(|symbol| self.projected_parameters.get(&symbol))
            .cloned()
        {
            let path = match path {
                Some(path) => Some(append_path(prefix, &path)),
                None => prefix,
            };
            self.mark_access(name, path, call);
            return;
        }
        let external = id
            .reference_id
            .get()
            .map(|id| self.scoping.get_reference(id))
            .is_some_and(|reference| {
                reference.symbol_id().is_none_or(|symbol| {
                    self.scoping.symbol_scope_id(symbol) == self.scoping.root_scope_id()
                })
            });
        if external {
            self.mark_access(id.name.to_string(), path, call);
        }
    }
    fn mark_access(&mut self, name: String, path: Option<String>, call: bool) {
        if self.coercing != 0 {
            self.coercions
                .entry((name.clone(), path.clone(), self.native_coercion.clone()))
                .and_modify(|hint| *hint |= self.coercing)
                .or_insert(self.coercing);
        }
        self.accesses
            .entry((name, path))
            .and_modify(|previous| *previous |= call)
            .or_insert(call);
    }
    fn new(scoping: &'s Scoping, factories: &'s HashMap<SymbolId, String>) -> Self {
        Self {
            scoping,
            factories,
            reads: BTreeSet::new(),
            writes: BTreeSet::new(),
            globals: BTreeSet::new(),
            has_mutation: false,
            retained_local_state: false,
            local_references: Vec::new(),
            local_member_paths: BTreeSet::new(),
            result_projections: BTreeSet::new(),
            local_objects: HashMap::new(),
            local_call_values: HashMap::new(),
            projected_parameters: HashMap::new(),
            function_depth: 0,
            skip_nested_functions: false,
            eager_functions: BTreeSet::new(),
            calls: BTreeSet::new(),
            call_counts: BTreeMap::new(),
            reference_counts: BTreeMap::new(),
            accesses: BTreeMap::new(),
            coercions: BTreeMap::new(),
            effects: Vec::new(),
            native_coercion: None,
            coercing: 0,
            in_member_root: false,
            input_span: None,
            inputs: BTreeSet::new(),
        }
    }
    fn binding(
        self,
        name: String,
        declaration: &str,
        value: &str,
        alias: Option<String>,
        factory: Option<String>,
        span: oxc_span::Span,
    ) -> Binding {
        let retained_local_state = self.retains_local_state();
        let retained_local_calls = self.retained_local_calls();
        Binding {
            name,
            declaration_kind: declaration.into(),
            value_kind: value.into(),
            alias,
            factory,
            reads: self.reads,
            writes: self.writes,
            globals: self.globals,
            has_mutation: self.has_mutation,
            retained_local_state,
            retained_local_calls,
            result_projections: self.result_projections,
            calls: self.calls,
            call_counts: self
                .call_counts
                .into_iter()
                .map(|(name, count)| CallCount { name, count })
                .collect(),
            reference_counts: self
                .reference_counts
                .into_iter()
                .map(|(name, count)| CallCount { name, count })
                .collect(),
            shape: ValueShape::default(),
            effects: self.effects,
            coercions: self
                .coercions
                .into_iter()
                .map(|((name, path, native), hint)| Coercion {
                    name,
                    path,
                    hint,
                    native,
                })
                .collect(),
            accesses: self
                .accesses
                .into_iter()
                .map(|((name, path), call)| Access { name, path, call })
                .collect(),
            span_start: span.start,
            span_end: span.end,
        }
    }
}
impl<'a> Visit<'a> for References<'_> {
    fn visit_template_literal(&mut self, literal: &TemplateLiteral<'a>) {
        for value in &literal.expressions {
            self.record_coercion(value, 1);
        }
        walk::walk_template_literal(self, literal);
    }
    fn visit_binary_expression(&mut self, expression: &BinaryExpression<'a>) {
        match expression.operator.as_str() {
            "===" | "!==" | "instanceof" => {}
            "in" => self.record_coercion(&expression.left, 1),
            _ => {
                self.record_coercion(&expression.left, 2);
                self.record_coercion(&expression.right, 2);
            }
        }
        walk::walk_binary_expression(self, expression);
    }

    fn visit_function(&mut self, function: &Function<'a>, flags: ScopeFlags) {
        if self.skip_nested_functions
            && self.function_depth > 0
            && !self.eager_functions.contains(&function.span.start)
        {
            return;
        }
        self.function_depth += 1;
        walk::walk_function(self, function, flags);
        self.function_depth -= 1;
    }
    fn visit_arrow_function_expression(&mut self, function: &ArrowFunctionExpression<'a>) {
        if self.skip_nested_functions
            && self.function_depth > 0
            && !self.eager_functions.contains(&function.span.start)
        {
            return;
        }
        self.function_depth += 1;
        walk::walk_arrow_function_expression(self, function);
        self.function_depth -= 1;
    }
    fn visit_variable_declarator(&mut self, declaration: &VariableDeclarator<'a>) {
        if let BindingPattern::BindingIdentifier(id) = &declaration.id {
            if let Some(symbol) = id.symbol_id.get() {
                if self.scoping.symbol_scope_id(symbol) != self.scoping.root_scope_id() {
                    let (kind, _, factory) = declaration
                        .init
                        .as_ref()
                        .map(|init| value_kind(init, self.scoping, self.factories))
                        .unwrap_or(("uninitialized", None, None));
                    let mutated = self.scoping.symbol_is_mutated(symbol);
                    let primitive_call = declaration.init.as_ref().is_some_and(|init| {
                        if let Expression::CallExpression(call) = init.get_inner_expression() {
                            if let Expression::Identifier(id) = call.callee.get_inner_expression() {
                                return id.reference_id.get().is_some_and(|id| {
                                    self.scoping.get_reference(id).symbol_id().is_none()
                                }) && matches!(
                                    id.name.as_str(),
                                    "String"
                                        | "Number"
                                        | "Boolean"
                                        | "BigInt"
                                        | "Symbol"
                                        | "parseInt"
                                        | "parseFloat"
                                        | "isFinite"
                                        | "isNaN"
                                );
                            }
                        }
                        false
                    });
                    if kind == "call" && !mutated && !primitive_call {
                        self.local_call_values.insert(
                            symbol,
                            (
                                self.function_depth,
                                factory.unwrap_or_else(|| "<dynamic>".into()),
                            ),
                        );
                    } else if mutated
                        || declaration.init.as_ref().is_some_and(|init| {
                            matches!(
                                init.get_inner_expression(),
                                Expression::NewExpression(_)
                                    | Expression::ObjectExpression(_)
                                    | Expression::ArrayExpression(_)
                            )
                        })
                    {
                        self.local_objects.insert(symbol, self.function_depth);
                    } else if let Some(init) = &declaration.init {
                        if let Some((alias, _, _)) = write_path(init) {
                            if let Some(alias) = alias
                                .reference_id
                                .get()
                                .and_then(|id| self.scoping.get_reference(id).symbol_id())
                            {
                                if let Some(depth) = self.local_objects.get(&alias).copied() {
                                    self.local_objects.insert(symbol, depth);
                                }
                                if let Some(value) = self.local_call_values.get(&alias).cloned() {
                                    self.local_call_values.insert(symbol, value);
                                }
                            }
                        }
                    }
                }
            }
        }
        walk::walk_variable_declarator(self, declaration);
    }

    fn visit_computed_member_expression(&mut self, member: &ComputedMemberExpression<'a>) {
        self.record_coercion(&member.expression, 1);
        self.result_projection(
            &member.object,
            static_property(&member.expression).unwrap_or("[computed]"),
        );
        let previous = self.in_member_root;
        let receiver = receiver_root(&member.object);
        if !previous && receiver {
            let value = if let Some(key) = static_property(&member.expression) {
                projected_shape(
                    value_shape(&member.object, self.scoping, self.factories, 0),
                    key,
                )
            } else {
                ValueShape {
                    kind: "computed_projection".into(),
                    values: vec![
                        value_shape(&member.object, self.scoping, self.factories, 0),
                        value_shape(&member.expression, self.scoping, self.factories, 0),
                    ],
                    ..Default::default()
                }
            };
            self.record_effect(CallEffect {
                value,
                hint: 0,
                native: None,
                option: None,
            });
        }
        let access = static_access(&member.object)
            .map(|(id, path)| (id, if path.is_empty() { None } else { Some(path) }, false))
            .or_else(|| write_path(&member.object));
        if !previous {
            if let Some((root, path, _)) = &access {
                self.record_root(
                    root,
                    Some(append_path(
                        path.clone(),
                        static_property(&member.expression).unwrap_or("[computed]"),
                    )),
                    false,
                );
            }
        }
        self.in_member_root = previous || access.is_some() || receiver;
        self.visit_expression(&member.object);
        self.in_member_root = false;
        self.visit_expression(&member.expression);
        self.in_member_root = previous;
    }
    fn visit_static_member_expression(&mut self, member: &StaticMemberExpression<'a>) {
        self.result_projection(&member.object, member.property.name.as_str());
        let previous = self.in_member_root;
        let receiver = receiver_root(&member.object);
        if !previous && receiver {
            self.record_effect(CallEffect {
                value: projected_shape(
                    value_shape(&member.object, self.scoping, self.factories, 0),
                    member.property.name.as_str(),
                ),
                hint: 0,
                native: None,
                option: None,
            });
        }
        let access = static_access(&member.object)
            .map(|(id, path)| (id, if path.is_empty() { None } else { Some(path) }, false))
            .or_else(|| write_path(&member.object));
        if !previous {
            if let Some((root, path, _)) = &access {
                self.record_root(
                    root,
                    Some(append_path(path.clone(), member.property.name.as_str())),
                    false,
                );
            }
        }
        self.in_member_root = previous || access.is_some() || receiver;
        walk::walk_static_member_expression(self, member);
        self.in_member_root = previous;
    }

    fn visit_call_expression(&mut self, call: &CallExpression<'a>) {
        if let Some((id, _, _)) = write_path(&call.callee) {
            if !module_reference(id, self.scoping)
                && id
                    .reference_id
                    .get()
                    .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_some())
            {
                let mut invocation = ValueShape {
                    kind: "call".into(),
                    callee_value: callee_shape(&call.callee, self.scoping, self.factories, 0),
                    member_call: matches!(
                        call.callee.get_inner_expression(),
                        Expression::StaticMemberExpression(_)
                            | Expression::ComputedMemberExpression(_)
                    ),
                    values: call
                        .arguments
                        .iter()
                        .map(|argument| {
                            argument
                                .as_expression()
                                .map_or_else(ValueShape::default, |value| {
                                    value_shape(value, self.scoping, self.factories, 0)
                                })
                        })
                        .collect(),
                    arguments_expanded: call
                        .arguments
                        .iter()
                        .any(|argument| matches!(argument, Argument::SpreadElement(_))),
                    ..Default::default()
                };
                invocation.name = Some(
                    static_access(&call.callee)
                        .map(|(id, path)| {
                            if path.is_empty() {
                                id.name.to_string()
                            } else {
                                format!("{}.{path}", id.name)
                            }
                        })
                        .unwrap_or_else(|| "<dynamic>".into()),
                );
                self.record_effect(CallEffect {
                    value: invocation,
                    hint: 0,
                    native: None,
                    option: None,
                });
            }
        }
        if let Some((id, path)) = static_access(&call.callee) {
            if id
                .reference_id
                .get()
                .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none())
            {
                let numeric = id.name == "Math"
                    && matches!(
                        path.as_str(),
                        "abs"
                            | "acos"
                            | "acosh"
                            | "asin"
                            | "asinh"
                            | "atan"
                            | "atanh"
                            | "atan2"
                            | "cbrt"
                            | "ceil"
                            | "clz32"
                            | "cos"
                            | "cosh"
                            | "exp"
                            | "expm1"
                            | "floor"
                            | "fround"
                            | "f16round"
                            | "hypot"
                            | "imul"
                            | "log"
                            | "log10"
                            | "log1p"
                            | "log2"
                            | "max"
                            | "min"
                            | "pow"
                            | "round"
                            | "sign"
                            | "sin"
                            | "sinh"
                            | "sqrt"
                            | "tan"
                            | "tanh"
                            | "trunc"
                    );
                if numeric {
                    let previous = self.native_coercion.replace("Math".into());
                    let count = if matches!(path.as_str(), "max" | "min" | "hypot") {
                        call.arguments.len()
                    } else if matches!(path.as_str(), "atan2" | "imul" | "pow") {
                        2
                    } else {
                        1
                    };
                    if call
                        .arguments
                        .iter()
                        .any(|argument| matches!(argument, Argument::SpreadElement(_)))
                    {
                        self.record_expanded_native(call, "Math", &path, 2);
                    } else {
                        for argument in call.arguments.iter().take(count) {
                            if let Some(value) = argument.as_expression() {
                                self.record_coercion(value, 2);
                            }
                        }
                    }
                    self.native_coercion = previous;
                }
                let key_index = if id.name == "Object" && path == "hasOwn" {
                    Some(1)
                } else if matches!(id.name.as_str(), "Math" | "JSON" | "Object")
                    && matches!(path.as_str(), "hasOwnProperty" | "propertyIsEnumerable")
                {
                    Some(0)
                } else {
                    None
                };
                if let Some(index) = key_index {
                    if call
                        .arguments
                        .iter()
                        .any(|argument| matches!(argument, Argument::SpreadElement(_)))
                    {
                        self.record_expanded_native(call, id.name.as_str(), &path, 1);
                    } else if let Some(value) =
                        call.arguments.get(index).and_then(Argument::as_expression)
                    {
                        let previous = self.native_coercion.replace(id.name.to_string());
                        self.record_coercion(value, 1);
                        self.native_coercion = previous;
                    }
                }
            }
        }
        let mut json_operation = false;
        if let Some((id, path)) = static_access(&call.callee) {
            if id.name == "JSON"
                && path == "stringify"
                && id
                    .reference_id
                    .get()
                    .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none())
            {
                json_operation = true;
                if call
                    .arguments
                    .iter()
                    .any(|argument| matches!(argument, Argument::SpreadElement(_)))
                {
                    self.record_expanded_native(call, "JSON", "stringify", 8);
                } else if let Some(value) = call.arguments.first().and_then(Argument::as_expression)
                {
                    self.record_effect(CallEffect {
                        value: value_shape(value, self.scoping, self.factories, 0),
                        hint: 8,
                        native: Some("JSON".into()),
                        option: call.arguments.get(1).and_then(Argument::as_expression).map(
                            |value| Box::new(value_shape(value, self.scoping, self.factories, 0)),
                        ),
                    });
                }
            }
        }
        if let Expression::Identifier(id) = call.callee.get_inner_expression() {
            if id
                .reference_id
                .get()
                .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none())
                && matches!(
                    id.name.as_str(),
                    "String"
                        | "Number"
                        | "BigInt"
                        | "Symbol"
                        | "parseInt"
                        | "parseFloat"
                        | "isFinite"
                        | "isNaN"
                )
            {
                if call
                    .arguments
                    .iter()
                    .any(|argument| matches!(argument, Argument::SpreadElement(_)))
                {
                    self.record_expanded_native(
                        call,
                        id.name.as_str(),
                        id.name.as_str(),
                        if matches!(
                            id.name.as_str(),
                            "String" | "Symbol" | "parseInt" | "parseFloat"
                        ) {
                            1
                        } else {
                            2
                        },
                    );
                } else if let Some(value) = call.arguments.first().and_then(Argument::as_expression)
                {
                    let previous = self.native_coercion.replace(id.name.to_string());
                    self.record_coercion(
                        value,
                        if matches!(
                            id.name.as_str(),
                            "String" | "Symbol" | "parseInt" | "parseFloat"
                        ) {
                            1
                        } else {
                            2
                        },
                    );
                    if id.name == "parseInt" {
                        if let Some(radix) = call.arguments.get(1).and_then(Argument::as_expression)
                        {
                            self.record_coercion(radix, 2);
                        }
                    }
                    self.native_coercion = previous;
                }
            }
        }
        if let Some((id, path, _)) = write_path(&call.callee) {
            let path = static_access(&call.callee)
                .map(|(_, path)| if path.is_empty() { None } else { Some(path) })
                .unwrap_or(path);
            self.record_root(id, path, true);
        }
        let name = static_access(&call.callee).map_or_else(
            || "<dynamic>".into(),
            |(id, path)| {
                if path.is_empty() {
                    id.name.to_string()
                } else {
                    format!("{}.{path}", id.name)
                }
            },
        );
        *self.call_counts.entry(name.clone()).or_default() += 1;
        self.calls.insert(name);
        // Native iteration callbacks project their element parameter back to
        // the source array. Lexical symbols keep shadowed parameters distinct.
        let mut projected = Vec::new();
        let mut eager_callback = None;
        if let Expression::StaticMemberExpression(member) = call.callee.get_inner_expression() {
            if matches!(
                member.property.name.as_str(),
                "map"
                    | "filter"
                    | "flatMap"
                    | "find"
                    | "findIndex"
                    | "findLast"
                    | "findLastIndex"
                    | "some"
                    | "every"
                    | "forEach"
            ) {
                if let Some(callback) = call.arguments.first().and_then(Argument::as_expression) {
                    if matches!(
                        callback.get_inner_expression(),
                        Expression::ArrowFunctionExpression(_) | Expression::FunctionExpression(_)
                    ) {
                        eager_callback = Some(callback.get_inner_expression().span().start);
                    }
                }
                if let Some((root, path, _)) = write_path(&member.object) {
                    let origin = root
                        .reference_id
                        .get()
                        .and_then(|id| self.scoping.get_reference(id).symbol_id())
                        .and_then(|symbol| self.projected_parameters.get(&symbol))
                        .cloned()
                        .map(|(name, prefix)| {
                            (
                                name,
                                match path.clone() {
                                    Some(path) => Some(append_path(prefix, &path)),
                                    None => prefix,
                                },
                            )
                        })
                        .or_else(|| {
                            if module_reference(root, self.scoping)
                                || root.reference_id.get().is_some_and(|id| {
                                    self.scoping.get_reference(id).symbol_id().is_none()
                                })
                            {
                                Some((root.name.to_string(), path))
                            } else {
                                None
                            }
                        });
                    if let Some((name, path)) = origin {
                        if let Some(callback) =
                            call.arguments.first().and_then(Argument::as_expression)
                        {
                            let params = match callback.get_inner_expression() {
                                Expression::ArrowFunctionExpression(f) => Some(&f.params),
                                Expression::FunctionExpression(f) => Some(&f.params),
                                _ => None,
                            };
                            if let Some(BindingPattern::BindingIdentifier(id)) =
                                params.and_then(|p| p.items.first()).map(|p| &p.pattern)
                            {
                                if let Some(symbol) = id.symbol_id.get() {
                                    let previous = self.projected_parameters.insert(
                                        symbol,
                                        (name, Some(append_path(path, "[computed]"))),
                                    );
                                    projected.push((symbol, previous));
                                }
                            }
                        }
                    }
                }
            }
        }
        let previous_skip = self.skip_nested_functions;
        if json_operation {
            self.skip_nested_functions = true;
        }
        if let Some(span) = eager_callback {
            self.eager_functions.insert(span);
        }
        walk::walk_call_expression(self, call);
        if let Some(span) = eager_callback {
            self.eager_functions.remove(&span);
        }
        self.skip_nested_functions = previous_skip;
        for (symbol, previous) in projected {
            if let Some(previous) = previous {
                self.projected_parameters.insert(symbol, previous);
            } else {
                self.projected_parameters.remove(&symbol);
            }
        }
    }

    fn visit_assignment_expression(&mut self, expression: &AssignmentExpression<'a>) {
        self.has_mutation = true;
        walk::walk_assignment_expression(self, expression);
    }
    fn visit_update_expression(&mut self, expression: &UpdateExpression<'a>) {
        self.has_mutation = true;
        walk::walk_update_expression(self, expression);
    }
    fn visit_unary_expression(&mut self, expression: &UnaryExpression<'a>) {
        if matches!(expression.operator.as_str(), "+" | "-" | "~") {
            self.record_coercion(&expression.argument, 2);
        }
        if expression.operator.as_str() == "delete" {
            self.has_mutation = true;
        }
        walk::walk_unary_expression(self, expression);
    }
    fn visit_this_expression(&mut self, _: &ThisExpression) {
        self.globals.insert("this".into());
        if !self.in_member_root {
            self.record_effect(CallEffect {
                value: ValueShape {
                    kind: "receiver".into(),
                    ..Default::default()
                },
                hint: 0,
                native: None,
                option: None,
            });
        }
    }

    fn visit_identifier_reference(&mut self, id: &IdentifierReference<'a>) {
        if module_reference(id, self.scoping)
            || id
                .reference_id
                .get()
                .is_some_and(|id| self.scoping.get_reference(id).symbol_id().is_none())
        {
            *self
                .reference_counts
                .entry(id.name.to_string())
                .or_default() += 1;
        }
        let Some(reference) = id
            .reference_id
            .get()
            .map(|id| self.scoping.get_reference(id))
        else {
            return;
        };
        if let Some(symbol) = reference.symbol_id() {
            if self.scoping.symbol_scope_id(symbol) != self.scoping.root_scope_id() {
                self.local_references.push((symbol, self.function_depth));
            }
        }
        if let Some(depth) = reference
            .symbol_id()
            .and_then(|symbol| self.local_objects.get(&symbol))
        {
            if self.function_depth > *depth {
                self.retained_local_state = true;
            }
        }
        if reference.is_read() {
            if let (Some(span), Some(symbol)) = (self.input_span, reference.symbol_id()) {
                let declaration = self.scoping.symbol_span(symbol);
                if self.scoping.symbol_scope_id(symbol) != self.scoping.root_scope_id()
                    && !(span.start <= declaration.start && declaration.end <= span.end)
                {
                    self.inputs.insert(id.name.to_string());
                }
            }
        }
        if !self.in_member_root
            && reference.is_read()
            && reference
                .symbol_id()
                .is_some_and(|symbol| self.projected_parameters.contains_key(&symbol))
        {
            self.record_root(id, None, false);
        }
        if !self.in_member_root
            && reference.is_read()
            && reference.symbol_id().is_none_or(|symbol| {
                self.scoping.symbol_scope_id(symbol) == self.scoping.root_scope_id()
            })
        {
            self.mark_access(id.name.to_string(), None, false);
        }
        match reference.symbol_id() {
            Some(symbol)
                if self.scoping.symbol_scope_id(symbol) == self.scoping.root_scope_id() =>
            {
                if reference.is_read() {
                    self.reads.insert(id.name.to_string());
                }
                if reference.is_write() {
                    self.writes.insert(id.name.to_string());
                }
            }
            None => {
                if reference.is_read() || reference.is_write() {
                    self.globals.insert(id.name.to_string());
                }
            }
            _ => {}
        }
    }
}

fn static_access<'s, 'a>(
    expression: &'s Expression<'a>,
) -> Option<(&'s IdentifierReference<'a>, String)> {
    match expression.get_inner_expression() {
        Expression::Identifier(id) => Some((id, String::new())),
        Expression::StaticMemberExpression(member) => {
            let (id, mut path) = static_access(&member.object)?;
            if !path.is_empty() {
                path.push('.');
            }
            path.push_str(member.property.name.as_str());
            Some((id, path))
        }
        Expression::ComputedMemberExpression(member) => {
            let property = match member.expression.get_inner_expression() {
                Expression::NumericLiteral(value)
                    if value.value >= 0.0
                        && value.value <= u32::MAX as f64
                        && value.value.fract() == 0.0 =>
                {
                    value.value.to_string()
                }
                _ => static_property(&member.expression)?.to_string(),
            };
            let (id, mut path) = static_access(&member.object)?;
            if !path.is_empty() {
                path.push('.');
            }
            path.push_str(&property);
            Some((id, path))
        }
        _ => None,
    }
}

fn static_property<'s>(expression: &'s Expression<'_>) -> Option<&'s str> {
    match expression.get_inner_expression() {
        Expression::StringLiteral(value)
            if !value.value.is_empty() && !value.value.contains('.') =>
        {
            Some(value.value.as_str())
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::analyze;
    #[test]
    fn logical_conditional_and_sequence_results_keep_branch_and_literal_facts() {
        let facts = analyze(
            r#"
            const choose=(flag,left,right)=>flag?left:right;
            const fallback=(left,right)=>left||right;
            const last=(left,right)=>(left,right);
            const absent=()=>null;
            const falsy=()=>false;
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let returned = |name: &str| {
            &facts
                .bindings
                .iter()
                .find(|b| b.name == name)
                .unwrap()
                .shape
                .returns[0]
        };
        assert_eq!(returned("choose").kind, "conditional");
        assert_eq!(returned("choose").values.len(), 3);
        assert_eq!(returned("fallback").kind, "logical");
        assert_eq!(returned("fallback").name.as_deref(), Some("||"));
        assert_eq!(returned("last").kind, "sequence");
        assert_eq!(returned("last").values[0].parameter_index, Some(1));
        assert_eq!(returned("absent").nullish, Some(true));
        assert_eq!(returned("falsy").truthy, Some(false));
    }

    #[test]
    fn parameterized_return_shapes_preserve_defaults_destructuring_rest_and_spreads() {
        let facts = analyze(
            r#"
            function identity(value){return value}
            function defaults(first,second=first){return second}
            function destructure({item}){return item}
            function local(source){const [item]=source;return item}
            function rest(...items){return items[0]}
            const expanded=identity(...inputs);
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let binding = |name: &str| facts.bindings.iter().find(|b| b.name == name).unwrap();
        assert_eq!(
            binding("identity").shape.returns[0].parameter_index,
            Some(0)
        );
        let default = &binding("defaults").shape.returns[0];
        assert_eq!(default.parameter_index, Some(1));
        assert_eq!(default.values[0].parameter_index, Some(0));
        for (name, path) in [("destructure", "item"), ("local", "0"), ("rest", "0")] {
            let returned = &binding(name).shape.returns[0];
            assert_eq!(returned.kind, "projection");
            assert_eq!(returned.path.as_deref(), Some(path));
            assert_eq!(returned.values[0].parameter_index, Some(0));
        }
        assert!(binding("rest").shape.returns[0].values[0].rest_parameter);
        assert!(binding("expanded").shape.arguments_expanded);
    }

    #[test]
    fn coercion_operands_are_distinct_from_truthiness_and_strict_identity_reads() {
        let facts = analyze(
            r#"
            const view={toString:()=>0};
            const direct=()=>String(view);
            const literal=()=>`${view}`;
            const numeric=()=>view+1;
            const unary=()=>-view;
            const equality=()=>view===view;
            const truthy=()=>Boolean(view);
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        for name in ["direct", "literal", "numeric", "unary"] {
            let binding = facts.bindings.iter().find(|b| b.name == name).unwrap();
            assert!(binding
                .coercions
                .iter()
                .any(|a| a.name == "view" && a.path.is_none()));
        }
        assert_eq!(
            facts
                .bindings
                .iter()
                .find(|b| b.name == "direct")
                .unwrap()
                .coercions[0]
                .hint,
            1
        );
        assert_eq!(
            facts
                .bindings
                .iter()
                .find(|b| b.name == "numeric")
                .unwrap()
                .coercions[0]
                .hint,
            2
        );
        for name in ["equality", "truthy"] {
            assert!(facts
                .bindings
                .iter()
                .find(|b| b.name == name)
                .unwrap()
                .coercions
                .is_empty());
        }
    }

    #[test]
    fn cyclic_and_expanding_return_aliases_have_bounded_shape_resolution() {
        let mut source = String::from("function make(){const root={a:()=>root,b:()=>root};");
        for index in 0..24 {
            source.push_str(&format!(
                "const node{index}={{a:{},b:{}}};",
                if index == 0 {
                    "root".into()
                } else {
                    format!("node{}", index - 1)
                },
                if index == 0 {
                    "root".into()
                } else {
                    format!("node{}", index - 1)
                }
            ));
        }
        source.push_str("return node23}");
        let facts = analyze(&source, "state.ts");
        assert!(facts.ok);
        let json = serde_json::to_string(&facts).unwrap();
        assert!(
            json.len() < 2_000_000,
            "return provenance must not expand cyclic/diamond aliases without a bound"
        );
    }

    #[test]
    fn nested_alias_targets_defaults_and_loops_keep_independent_sources() {
        let facts = analyze(
            r#"
            import {observable} from 'weiv:observable'; import {library} from 'outside';
            const state={child:{count:0}};
            function update(){const alias=state;
                ({nested:{child:alias.child}}=library.getState());
                ({child:alias.child=library.getState()}=observable({}));
                for([alias.child] of library.getState()){}
                for(alias.child in library){}
            }
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        for operator in ["=", "default", "for-of", "for-in"] {
            let incoming = facts
                .assignments
                .iter()
                .find(|a| a.target == "state" && a.operator == operator)
                .unwrap();
            assert!(incoming.projected && incoming.dynamic_path);
            if operator == "for-in" {
                assert!(incoming.value.reads.is_empty());
            } else {
                assert!(incoming.value.reads.contains("library"));
            }
        }
    }

    #[test]
    fn helper_returns_resolve_local_shapes_without_eagerly_invoking_callbacks() {
        let facts = analyze(
            r#"
            import {snapshot} from 'weiv:observable';import {library} from 'outside';
            const callback=()=>0;
            function make(){const captured=snapshot({callback});return captured}
            function sibling(){return {count:1,unused:()=>library.count}}
            const projected=()=>{const parent={child:{count:1}};return parent.child};
            function capture(){const count=2;return {read:()=>count}}
            async function deferred(){return {count:1}}
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let binding = |name: &str| facts.bindings.iter().find(|b| b.name == name).unwrap();
        let returned = &binding("make").shape.returns[0];
        assert_eq!(returned.kind, "call");
        assert_eq!(returned.factory.as_deref(), Some("snapshot"));
        assert_eq!(binding("projected").shape.returns[0].kind, "projection");
        assert!(binding("sibling")
            .shape
            .invocation
            .as_ref()
            .unwrap()
            .accesses
            .iter()
            .all(|a| a.name != "library"));
        let read = &binding("capture").shape.returns[0].properties[0].value;
        assert!(read.captured_locals.is_empty());
        assert!(binding("deferred").shape.async_result);
    }

    #[test]
    fn alias_member_writes_retain_sources_without_retargeting_reassigned_aliases() {
        let facts = analyze(
            r#"
            import {library} from 'outside';
            const state={child:{count:0}};
            function mutate(){const holder={target:state};const {target:alias}=holder;alias.child=library.getState()}
            function rebind(){let alias=state;alias=library.getState()}
            function shadow(state){state.child=library.getState()}
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let incoming: Vec<_> = facts
            .assignments
            .iter()
            .filter(|a| a.target == "state")
            .collect();
        assert_eq!(incoming.len(), 1);
        assert_eq!(incoming[0].path.as_deref(), Some("child"));
        assert!(incoming[0].projected && incoming[0].dynamic_path);
        assert!(incoming[0].value.reads.contains("library"));
    }

    #[test]
    fn reflective_argument_aliases_preserve_indirection_spread_and_shadowing() {
        let facts = analyze(
            r#"
            const state={count:0};
            function update(next){
                const invoke=()=>Reflect.apply(Object.assign,null,args);
                let args=[]; args=[state,next]; invoke();
                Object.assign(...args);
                const holder={destination:state}; const {destination}=holder;
                Object.assign(destination,next);
            }
            function shadow(state){Reflect.apply(Object.assign,null,[state,{count:1}])}
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let flows: Vec<_> = facts
            .argument_flows
            .iter()
            .filter(|flow| flow.target == "state")
            .collect();
        assert!(flows
            .iter()
            .any(|flow| flow.callee == "global:Reflect.apply"
                && flow.indirect
                && flow.argument_index == 2));
        assert!(flows
            .iter()
            .any(|flow| flow.callee == "global:Object.assign" && flow.spread && flow.indirect));
        assert!(flows
            .iter()
            .any(|flow| flow.callee == "global:Object.assign"
                && !flow.spread
                && flow.indirect
                && flow.argument_index == 0));
        assert_eq!(
            flows
                .iter()
                .filter(|flow| flow.callee == "global:Reflect.apply")
                .count(),
            1
        );
    }

    #[test]
    fn retained_local_calls_and_forward_captures_keep_explicit_contract_provenance() {
        let facts = analyze(
            r#"
            import {observable as track} from 'weiv:observable';
            import {track as externalTrack} from './api';
            import {create} from 'outside';
            function callResult(){const item=create();return ()=>item.count}
            function explicit(){const item=track({count:0});return ()=>item.count}
            function external(){const item=externalTrack({count:0});return ()=>item.count}
            function forward(){const read=()=>count;let count;count=0;return read}
            function pure(){const count=Number(2);return ()=>count}
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let binding = |name: &str| facts.bindings.iter().find(|b| b.name == name).unwrap();
        assert!(binding("callResult")
            .retained_local_calls
            .contains("create"));
        assert!(!binding("explicit").retained_local_state);
        assert!(binding("explicit").retained_local_calls.is_empty());
        assert!(binding("external")
            .retained_local_calls
            .contains("externalTrack"));
        assert!(binding("forward").retained_local_state);
        assert!(!binding("pure").retained_local_state);
        assert!(binding("pure").retained_local_calls.is_empty());
    }

    #[test]
    fn retained_factory_objects_and_indirect_destination_flows_are_explicit() {
        let facts = analyze(
            r#"
            function make(){const item={count:0};return {item,increment(){item.count++}}}
            function pure(){let total=0;for(let i=0;i<3;i++)total+=i;return total}
            const state={count:0}; const assign=Object.assign;
            function forward(target,next){Object.assign(target,next)}
            function update(next){assign(state,next);forward(state,next)}
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        assert!(
            facts
                .bindings
                .iter()
                .find(|b| b.name == "make")
                .unwrap()
                .retained_local_state
        );
        assert!(
            !facts
                .bindings
                .iter()
                .find(|b| b.name == "pure")
                .unwrap()
                .retained_local_state
        );
        for callee in ["assign", "forward"] {
            assert!(facts
                .argument_flows
                .iter()
                .any(|flow| flow.target == "state" && flow.callee == callee));
        }
    }

    #[test]
    fn json_effects_preserve_hooks_without_eagerly_invoking_callbacks() {
        let facts = analyze("let count=0; const render=()=>JSON.stringify({toJSON(){return {count:this.count}},unused:()=>count}); const arrow=()=>({toJSON:()=>({count})});", "state.ts");
        assert!(facts.ok);
        let render = &facts.bindings[1];
        let effect = render
            .effects
            .iter()
            .find(|effect| effect.hint == 8)
            .unwrap();
        assert_eq!(effect.native.as_deref(), Some("JSON"));
        let hook = &effect.value.properties[0].value;
        assert!(!hook.lexical_this);
        let receiver = &hook.returns[0].properties[0].value;
        assert_eq!(receiver.kind, "projection");
        assert_eq!(receiver.path.as_deref(), Some("count"));
        assert_eq!(receiver.values[0].kind, "receiver");
        assert!(!render
            .shape
            .invocation
            .as_ref()
            .unwrap()
            .accesses
            .iter()
            .any(|access| access.name == "count"));
        let arrow = &facts.bindings[2].shape.returns[0].properties[0].value;
        assert!(arrow.lexical_this);
        assert!(arrow.accesses.iter().any(|access| access.name == "count"));
        let iterated = analyze("let count=0;const rows=[];const render=()=>JSON.stringify(rows.map(({value})=>{const next=value+count;return {next,unused:()=>count};}));", "state.ts");
        let render = &iterated.bindings[2];
        assert!(render
            .shape
            .invocation
            .as_ref()
            .unwrap()
            .accesses
            .iter()
            .any(|access| access.name == "count"));
    }

    #[test]
    fn method_calls_keep_receiver_form_and_computed_key_provenance() {
        let facts = analyze("function invoke(holder,key){return holder[key]()}function unbound(holder){const read=holder.read;return read()}const holder={count:0,read(){return [{valueOf:()=>this.count}]}};", "state.ts");
        assert!(facts.ok);
        let computed = &facts.bindings[0].shape.returns[0];
        assert!(computed.member_call);
        let callee = computed.callee_value.as_ref().unwrap();
        assert_eq!(callee.kind, "computed_projection");
        assert_eq!(callee.values[1].parameter_index, Some(1));
        assert!(!facts.bindings[1].shape.returns[0].member_call);
        let method = &facts.bindings[2].shape.properties[1].value;
        let arrow = &method.returns[0].values[0].properties[0].value;
        assert!(arrow.lexical_this);
        assert_eq!(arrow.invocation.as_ref().unwrap().scope_id, method.scope_id);
        let receiver = &arrow.invocation.as_ref().unwrap().effects[0].value.values[0];
        assert_eq!(receiver.kind, "receiver");
        assert_eq!(receiver.scope_id, method.scope_id);
    }

    #[test]
    fn constructing_a_method_callback_does_not_execute_its_body() {
        let facts = analyze(
            "const render=()=>invoke(value=>value.read(),holder);",
            "template.ts",
        );
        assert!(facts.ok);
        assert!(!facts.bindings[0]
            .effects
            .iter()
            .any(|effect| effect.value.name.as_deref() == Some("value.read")));
        let callback = &facts.bindings[0].shape.returns[0].values[0];
        let effect = &callback.invocation.as_ref().unwrap().effects[0];
        assert_eq!(effect.value.name.as_deref(), Some("value.read"));
        assert!(effect.value.member_call);
        assert_eq!(
            effect.value.callee_value.as_ref().unwrap().values[0].scope_id,
            callback.scope_id
        );
    }

    #[test]
    fn nested_invocation_locals_do_not_expand_deferred_returns() {
        let source = format!("const callback={}0;", "()=>".repeat(80));
        let facts = analyze(&source, "state.ts");
        assert!(facts.ok);
        // Deep source remains bounded even though both immediate effects and
        // deferred returns are recorded for each callable.
        assert!(serde_json::to_string(&facts).unwrap().len() < 200_000);
        let mut shape = &facts.bindings[0].shape;
        let mut depth = 0;
        while shape.kind == "function" && !shape.returns.is_empty() {
            depth += 1;
            shape = &shape.returns[0];
        }
        assert!(depth > 1 && depth <= 32);
    }

    #[test]
    fn nested_parameters_keep_defining_scopes_through_callback_and_json_returns() {
        let facts = analyze("function bind(value){return argument=>({toJSON:key=>({value,argument,key})})}function invoke(callback,value){return callback(value)}", "state.ts");
        assert!(facts.ok);
        let bind = &facts.bindings[0].shape;
        let callback = &bind.returns[0];
        let hook = &callback.returns[0].properties[0].value;
        assert_ne!(bind.scope_id, callback.scope_id);
        assert_ne!(callback.scope_id, hook.scope_id);
        let fields = &hook.returns[0].properties;
        for (field, owner) in fields
            .iter()
            .zip([bind.scope_id, callback.scope_id, hook.scope_id])
        {
            assert_eq!(field.value.kind, "parameter");
            assert_eq!(field.value.parameter_index, Some(0));
            assert_eq!(field.value.scope_id, owner);
        }
        let invoke = &facts.bindings[1].shape;
        let call = &invoke.returns[0];
        assert_eq!(call.callee_value.as_ref().unwrap().kind, "parameter");
        assert_eq!(
            call.callee_value.as_ref().unwrap().scope_id,
            invoke.scope_id
        );
        assert_eq!(
            invoke.invocation.as_ref().unwrap().effects[0]
                .value
                .name
                .as_deref(),
            Some("callback")
        );
    }

    #[test]
    fn native_spread_effects_keep_argument_positions_and_radix_conversion() {
        let facts = analyze("const values=[];const render=()=>Math.max(1,...values,2);const json=()=>JSON.stringify(...values);const parse=()=>parseInt('10',radix);", "state.ts");
        assert!(facts.ok);
        let effect = &facts.bindings[1].effects[0];
        assert_eq!(effect.native.as_deref(), Some("Math"));
        assert_eq!(effect.value.kind, "native_arguments");
        assert_eq!(effect.value.callee.as_deref(), Some("max"));
        assert_eq!(effect.value.values.len(), 3);
        assert_eq!(effect.value.values[1].kind, "spread");
        assert_eq!(
            effect.value.values[1].values[0].name.as_deref(),
            Some("values")
        );
        assert_eq!(facts.bindings[2].effects[0].hint, 8);
        assert!(facts.bindings[3]
            .coercions
            .iter()
            .any(|coercion| coercion.name == "radix" && coercion.hint == 2));
        let mutated = analyze(
            "const values=[0];function change(){const alias=values;alias.pop()}",
            "state.ts",
        );
        assert!(mutated.iterable_mutations.contains("values"));
        let parameterized = analyze(
            "function maximum(args){const forwarded=args;return Math.max(...forwarded)}",
            "state.ts",
        );
        let invocation = parameterized.bindings[0].shape.invocation.as_ref().unwrap();
        assert_eq!(
            invocation.effects[0].value.values[0].values[0].kind,
            "parameter"
        );
        assert_eq!(
            invocation.effects[0].value.values[0].values[0].parameter_index,
            Some(0)
        );
    }

    #[test]
    fn native_member_call_shapes_keep_the_complete_receiver_chain() {
        let facts = analyze("const rows=[]; const render=()=>rows.map(row=>row.count).join(','); const converted=()=>String(get());", "state.ts");
        assert!(facts.ok);
        let joined = &facts.bindings[1].shape.returns[0];
        let join = joined.callee_value.as_ref().unwrap();
        assert_eq!(join.path.as_deref(), Some("join"));
        let map = join.values[0].callee_value.as_ref().unwrap();
        assert_eq!(map.path.as_deref(), Some("map"));
        assert_eq!(map.values[0].name.as_deref(), Some("rows"));
        let effect = &facts.bindings[2].effects[0];
        assert_eq!(effect.value.callee.as_deref(), Some("get"));
        assert_eq!(effect.native.as_deref(), Some("String"));
    }

    #[test]
    fn callback_parameters_project_to_arrays_and_call_results_stay_uncertain() {
        let facts = analyze(
            r#"
            const rows=[];
            const view=()=>rows.map(row=>row.callback.count).join();
            const call=()=>rows.some(row=>row.read());
            const projected=()=>get().callback.count;
        "#,
            "state.ts",
        );
        assert!(facts.ok);
        let view = facts.bindings.iter().find(|b| b.name == "view").unwrap();
        assert!(view
            .accesses
            .iter()
            .any(|a| a.name == "rows" && a.path.as_deref() == Some("[computed].callback.count")));
        assert!(view.result_projections.contains("rows.map().join"));
        let call = facts.bindings.iter().find(|b| b.name == "call").unwrap();
        assert!(call
            .accesses
            .iter()
            .any(|a| a.name == "rows" && a.path.as_deref() == Some("[computed].read") && a.call));
        assert!(facts
            .bindings
            .iter()
            .find(|b| b.name == "projected")
            .unwrap()
            .result_projections
            .contains("get().callback"));
    }

    #[test]
    fn wrapped_shapes_preserve_callable_paths_and_lexical_call_uses() {
        let facts=analyze("import {snapshot as take} from 'weiv:observable'; const raw={n:0}; const captured=take({data:raw,read:()=>raw.n}); const use=()=>captured.read(); function shadow(raw){return take({read:()=>raw.n})}", "state.ts");
        assert!(facts.ok);
        let wrapped = &facts.bindings[1].shape;
        assert_eq!(wrapped.factory.as_deref(), Some("take"));
        assert_eq!(wrapped.values[0].properties[0].value.kind, "reference");
        let callable = &wrapped.values[0].properties[1].value;
        assert_eq!(callable.kind, "function");
        assert_eq!(callable.accesses[0].name, "raw");
        assert!(!callable.accesses[0].call);
        assert!(facts.bindings[2]
            .accesses
            .iter()
            .any(|access| access.name == "captured"
                && access.path.as_deref() == Some("read")
                && access.call));
        assert!(!facts.bindings[3].reads.contains("raw"));
    }
    #[test]
    fn mutator_inputs_preserve_data_sources_and_builtin_shadowing() {
        let facts=analyze("import {observable} from 'weiv:observable'; import {library} from 'outside'; const state={items:[]}; function replace(next,items){state.items.push(next); state.items.splice(0,1,...items); Object.assign(state,next); Object.defineProperty(state,'child',{value:observable(next),writable:true}); Reflect.set(state,'child',next); Object.defineProperties(state,{child:{value:library.getState(),writable:true}})} function shadow(Object,state,next){Object.assign(state,next);state.items.push(next)} function fake(Object,next){Object.assign(state,next)}", "state.ts");
        assert!(facts.ok);
        assert_eq!(facts.assignments.len(), 6);
        assert_eq!(facts.assignments[0].operator, "push");
        assert_eq!(facts.assignments[0].path.as_deref(), Some("items"));
        assert!(facts.assignments[1].inputs.contains("items"));
        assert_eq!(facts.assignments[2].operator, "Object.assign");
        assert_eq!(facts.assignments[3].value.value_kind, "observable");
        assert_eq!(facts.assignments[4].operator, "Reflect.set");
        assert_eq!(facts.assignments[5].operator, "Object.defineProperties");
        assert!(facts.assignments[5].value.reads.contains("library"));
    }
    #[test]
    fn incoming_patterns_defaults_and_iterations_preserve_projected_sources() {
        let facts=analyze("import {observable} from 'weiv:observable'; import {library} from 'outside'; let state={}; function replace(next,rows,key){state[key].child=next; ({part:state.child=library.getState()}=observable({})); for(state.child of rows){} for(state.key in library){}} function shadow(state,rows){for(state.child of rows){}}", "state.ts");
        assert!(facts.ok);
        assert_eq!(facts.assignments.len(), 5);
        assert_eq!(
            facts.assignments[0].path.as_deref(),
            Some("[computed].child")
        );
        assert!(facts.assignments[0].dynamic_path);
        assert!(facts.assignments[0].inputs.contains("next"));
        assert_eq!(facts.assignments[1].value.value_kind, "observable");
        assert_eq!(facts.assignments[2].operator, "default");
        assert_eq!(
            facts.assignments[2].value.factory.as_deref(),
            Some("library.getState")
        );
        assert_eq!(facts.assignments[3].operator, "for-of");
        assert!(facts.assignments[3].inputs.contains("rows"));
        assert_eq!(facts.assignments[4].operator, "for-in");
        assert_eq!(facts.assignments[4].value.value_kind, "primitive");
        assert!(facts.assignments[4].value.reads.is_empty());
    }
    #[test]
    fn module_sources_use_literal_spans_and_include_static_dynamic_imports() {
        let source = "const lazy=()=>import('./lazy'); import {state} from './state'; export * from './more'; const text='import fake from missing';";
        let facts = analyze(source, "state.ts");
        assert!(facts.ok);
        assert_eq!(
            facts
                .sources
                .iter()
                .map(|s| s.source.as_str())
                .collect::<Vec<_>>(),
            ["./lazy", "./state", "./more"]
        );
        for item in facts.sources {
            assert_eq!(
                &source[item.span_start as usize..item.span_end as usize],
                format!("'{}'", item.source)
            );
        }
        assert!(!facts.opaque_dynamic_import);
        assert!(
            analyze("export const lazy=(name)=>import(name)", "state.ts").opaque_dynamic_import
        );
        let opaque_source = "// λ\nexport const lazy=(name:string)=>import(name);";
        let opaque = analyze(opaque_source, "state.ts");
        assert_eq!(opaque.opaque_dynamic_imports.len(), 1);
        let span = &opaque.opaque_dynamic_imports[0];
        assert_eq!(
            &opaque_source[span.span_start as usize..span.span_end as usize],
            "import(name)"
        );
    }
    #[test]
    fn incoming_assignments_preserve_lexical_inputs_and_member_targets() {
        let facts = analyze("import {observable} from 'weiv:observable'; import {library} from 'outside'; let state={}; function replace(library){state=library;state.child=library.next();state[key]=observable({});} function shadow(state){state={};} state=library.getState(); state.make=(parameter)=>parameter;", "state.ts");
        assert!(facts.ok);
        assert_eq!(facts.assignments.len(), 5);
        assert_eq!(facts.assignments[0].value.value_kind, "input");
        assert!(facts.assignments[0].inputs.contains("library"));
        assert!(facts.assignments[0].value.alias.is_none());
        assert_eq!(facts.assignments[1].path.as_deref(), Some("child"));
        assert!(facts.assignments[1].value.factory.is_none());
        assert!(facts.assignments[2].dynamic_path);
        assert_eq!(facts.assignments[2].value.value_kind, "observable");
        assert_eq!(
            facts.assignments[3].value.factory.as_deref(),
            Some("library.getState")
        );
        assert!(facts.assignments[4].inputs.is_empty());
    }
    #[test]
    fn lexical_helper_reads_and_reexports() {
        let facts = analyze("import { store } from './store'; export function read(){return store.count} export function format(store){return store.count} export {read as value}; export {state as shared} from './state'; export * from './more';", "state.ts");
        assert!(facts.ok);
        assert!(!facts.managed);
        assert!(facts.bindings[0].reads.contains("store"));
        assert!(facts.bindings[1].reads.is_empty());
        assert_eq!(facts.exports[2].local.as_deref(), Some("read"));
        assert_eq!(facts.exports[3].imported.as_deref(), Some("state"));
        assert_eq!(facts.exports[4].kind, "star");
    }
    #[test]
    fn only_actual_observable_factories_are_recognized() {
        let facts = analyze("import {observable as obs,snapshot} from 'weiv:observable'; import * as api from 'weiv:observable'; export const state=obs({count:0}); const copied=snapshot(state); const nested=api.observable({}); function fake(obs){return obs({})} const raw={count:0}; const alias=state; export default alias;", "state.ts");
        assert_eq!(facts.bindings[0].value_kind, "observable");
        assert_eq!(facts.bindings[1].value_kind, "snapshot");
        assert_eq!(facts.bindings[2].value_kind, "observable");
        assert!(facts.bindings[3].reads.is_empty());
        assert_eq!(facts.bindings[4].value_kind, "object");
        assert_eq!(facts.bindings[5].alias.as_deref(), Some("state"));
        assert_eq!(facts.exports.last().unwrap().exported, "default");
    }
    #[test]
    fn root_reassignment_prevents_trusting_only_an_initializer() {
        let facts = analyze("import {observable} from 'weiv:observable'; export let state=observable({}); state={}; export function replace(next){state=next}", "state.ts");
        assert_eq!(facts.bindings[0].value_kind, "observable");
        assert!(facts.root_writes.contains("state"));
        assert!(facts.bindings[1].writes.contains("state"));
    }

    #[test]
    fn opaque_functions_and_parameter_mutation_are_not_proven_pure() {
        let facts=analyze("declare function read():number; export {read}; export function mutate(store){store.count++} export function receiver(){return this.count} export function invoke(value){return value.next()}", "state.ts");
        assert!(facts.ok);
        assert_eq!(facts.bindings[0].declaration_kind, "ambient");
        assert_eq!(facts.bindings[0].value_kind, "unknown");
        assert!(facts.bindings[1].has_mutation);
        assert!(facts.bindings[2].globals.contains("this"));
        assert!(facts.bindings[3].calls.contains("value.next"));
    }

    #[test]
    fn access_paths_preserve_namespace_members_and_bare_dynamic_uses() {
        let facts=analyze("import * as ns from './state'; export function read(rows,key){return [ns.value,ns,ns[key].field,rows.map(ns=>ns.count)]}", "state.ts");
        assert!(facts.ok);
        let paths = &facts.bindings[0].accesses;
        assert_eq!(paths.len(), 3);
        assert!(paths
            .iter()
            .any(|a| a.name == "ns" && a.path.as_deref() == Some("value")));
        assert!(paths.iter().any(|a| a.name == "ns" && a.path.is_none()));
        assert!(paths
            .iter()
            .any(|a| a.path.as_deref() == Some("[computed].field")));
    }

    #[test]
    fn default_expression_slots_cannot_collide_with_source_bindings() {
        let facts = analyze("const $default=1; export default {count:0};", "state.ts");
        assert!(facts.ok);
        assert_eq!(facts.bindings[0].name, "$default");
        assert_eq!(facts.bindings[1].name, "<default>");
        assert_eq!(facts.exports[0].local.as_deref(), Some("<default>"));
    }

    #[test]
    fn type_only_imports_and_exports_do_not_become_runtime_edges() {
        let facts=analyze("import type {Store} from './types'; export type {Store}; export const label='fixed'; export let count=0;", "state.ts");
        assert!(facts.imports.is_empty());
        assert_eq!(facts.exports.len(), 2);
        assert_eq!(facts.bindings[0].declaration_kind, "const");
        assert_eq!(facts.bindings[1].declaration_kind, "let");
    }

    #[test]
    fn root_destructuring_keeps_initial_shapes_even_when_a_binding_is_reassigned() {
        let facts=analyze("const shared={count:0};export let {first:state,...rest}={first:shared,last:{count:1}};export let [scalar,...rows]=[0,shared];function replace(){state={count:2}}", "state.ts");
        assert!(facts.ok);
        let state = facts
            .bindings
            .iter()
            .find(|binding| binding.name == "state")
            .unwrap();
        assert_eq!(state.value_kind, "destructured");
        assert_eq!(state.shape.kind, "reference");
        assert_eq!(state.shape.name.as_deref(), Some("shared"));
        assert!(facts.root_writes.contains("state"));
        let rest = facts
            .bindings
            .iter()
            .find(|binding| binding.name == "rest")
            .unwrap();
        assert_eq!(rest.shape.kind, "record");
        assert_eq!(rest.shape.properties.len(), 1);
        assert_eq!(rest.shape.properties[0].name.as_deref(), Some("last"));
        let rows = facts
            .bindings
            .iter()
            .find(|binding| binding.name == "rows")
            .unwrap();
        assert_eq!(rows.shape.kind, "array");
        assert_eq!(rows.shape.values[0].name.as_deref(), Some("shared"));
    }

    #[test]
    fn root_declaration_projection_is_distinct_from_parameter_projection() {
        let facts = analyze(
            "const source={item:{count:0}};let {item}=source;function read({item}){return item}",
            "state.ts",
        );
        assert!(facts.ok);
        assert_eq!(facts.bindings[1].shape.kind, "declaration_projection");
        assert_eq!(facts.bindings[2].shape.returns[0].kind, "projection");
    }
}
