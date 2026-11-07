mod cell_diagnostics;
mod cells;
mod declarations;
mod module_cells;
mod module_state;
mod template_expression;
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_codegen::{Codegen, CodegenOptions};
use oxc_parser::Parser;
use oxc_semantic::SemanticBuilder;
use oxc_span::{GetSpan, SourceType};
use oxc_transformer::{TransformOptions, Transformer};
use serde::Serialize;
use std::collections::BTreeSet;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;

#[derive(Serialize)]
struct ScriptAnalysisResponse {
    ok: bool,
    source_path: String,
    transpiled_code: String,
    props: Option<PropsRecord>,
    imports: Vec<ImportRecord>,
    bindings: Vec<BindingRecord>,
    state_analysis: StateAnalysisRecord,
    diagnostics: Vec<DiagnosticRecord>,
}

#[derive(Serialize, Default)]
struct StateAnalysisRecord {
    helpers: Vec<HelperRecord>,
    mutations: Vec<MutationRecord>,
    aliases: Vec<AliasRecord>,
    callback_registrations: Vec<CallbackRegistrationRecord>,
}

#[derive(Serialize, Default)]
struct PropsRecord {
    has_props_export: bool,
    props_binding_name: Option<String>,
    props_type_name: Option<String>,
}

#[derive(Serialize)]
struct ImportRecord {
    source: String,
    kind: String,
    imported_name: Option<String>,
    local_name: String,
    span_start: usize,
    span_end: usize,
}

#[derive(Serialize)]
struct BindingRecord {
    name: String,
    kind: String,
    exported: bool,
    template_visible: bool,
    callable: bool,
    type_annotation: Option<String>,
    span_start: usize,
    span_end: usize,
}

#[derive(Serialize, Default, Clone)]
struct HelperRecord {
    name: String,
    kind: String,
    span_start: usize,
    span_end: usize,
    reads: Vec<String>,
    writes: Vec<String>,
    calls: Vec<String>,
    async_flag: bool,
    returns_expression_only: bool,
    contains_external_reads: bool,
    contains_side_effects: bool,
}

#[derive(Serialize, Default, Clone)]
struct MutationRecord {
    binding: String,
    kind: String,
    span_start: usize,
    span_end: usize,
    statement_position: bool,
    member_path: Option<String>,
    inside_callback: bool,
    callback_owned_candidate: bool,
}

#[derive(Serialize, Default, Clone)]
struct AliasRecord {
    alias: String,
    target: String,
    kind: String,
    span_start: usize,
    span_end: usize,
}

#[derive(Serialize, Default, Clone)]
struct CallbackRegistrationRecord {
    callee: String,
    callback_kind: String,
    callback_span_start: usize,
    callback_span_end: usize,
    owned_candidate: bool,
    reason: String,
}

#[derive(Serialize)]
struct DiagnosticRecord {
    severity: String,
    message: String,
    span_start: usize,
    span_end: usize,
    line: u32,
    column: u32,
    code: Option<String>,
}

#[no_mangle]
pub extern "C" fn weiv_script_analyze(
    source: *const c_char,
    source_path: *const c_char,
) -> *mut c_char {
    let source = match parse_required_cstr(source) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let source_path = parse_optional_cstr(source_path).unwrap_or_else(|| "<script>".to_string());

    let source_type = SourceType::from_path(&source_path).unwrap_or(SourceType::ts());
    let allocator = Allocator::default();
    let parsed = Parser::new(&allocator, &source, source_type).parse();

    if !parsed.errors.is_empty() {
        let diagnostics = parsed
            .errors
            .iter()
            .map(|error| {
                let span = error.labels.as_ref().and_then(|labels| labels.first());
                let start = span.map_or(0, |label| label.offset());
                let end = span.map_or(start, |label| label.offset() + label.len());
                DiagnosticRecord {
                    severity: "error".to_string(),
                    message: error.to_string(),
                    span_start: start,
                    span_end: end,
                    line: 0,
                    column: 0,
                    code: Some("script.syntax".to_string()),
                }
            })
            .collect();

        let response = ScriptAnalysisResponse {
            ok: false,
            source_path,
            transpiled_code: String::new(),
            props: None,
            imports: Vec::new(),
            bindings: Vec::new(),
            state_analysis: StateAnalysisRecord::default(),
            diagnostics,
        };

        return to_json_ptr(&response);
    }

    let transpiled_code = transpile_source(&source, &source_path).unwrap_or_default();

    let mut response = ScriptAnalysisResponse {
        ok: true,
        source_path,
        transpiled_code,
        props: Some(PropsRecord::default()),
        imports: Vec::new(),
        bindings: Vec::new(),
        state_analysis: StateAnalysisRecord::default(),
        diagnostics: Vec::new(),
    };

    for statement in &parsed.program.body {
        match statement {
            Statement::ImportDeclaration(decl) => {
                let source_name = decl.source.value.as_str().to_string();
                let declaration_is_type_only = decl.import_kind == ImportOrExportKind::Type;
                match &decl.specifiers {
                    None => response.imports.push(ImportRecord {
                        source: source_name,
                        kind: "side_effect".to_string(),
                        imported_name: None,
                        local_name: String::new(),
                        span_start: decl.span.start as usize,
                        span_end: decl.span.end as usize,
                    }),
                    Some(specifiers) => {
                        for specifier in specifiers {
                            match specifier {
                                ImportDeclarationSpecifier::ImportSpecifier(spec) => {
                                    let is_type_only = declaration_is_type_only
                                        || spec.import_kind == ImportOrExportKind::Type;
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: if is_type_only {
                                            "type_named".to_string()
                                        } else {
                                            "named".to_string()
                                        },
                                        imported_name: Some(module_export_name(&spec.imported)),
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                                ImportDeclarationSpecifier::ImportDefaultSpecifier(spec) => {
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: "default".to_string(),
                                        imported_name: None,
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if declaration_is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !declaration_is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                                ImportDeclarationSpecifier::ImportNamespaceSpecifier(spec) => {
                                    let local_name = spec.local.name.as_str().to_string();
                                    response.imports.push(ImportRecord {
                                        source: source_name.clone(),
                                        kind: "namespace".to_string(),
                                        imported_name: Some("*".to_string()),
                                        local_name: local_name.clone(),
                                        span_start: decl.span.start as usize,
                                        span_end: decl.span.end as usize,
                                    });
                                    response.bindings.push(BindingRecord {
                                        name: local_name,
                                        kind: if declaration_is_type_only {
                                            "type_only".to_string()
                                        } else {
                                            "import".to_string()
                                        },
                                        exported: false,
                                        template_visible: !declaration_is_type_only,
                                        callable: false,
                                        type_annotation: None,
                                        span_start: spec.local.span.start as usize,
                                        span_end: spec.local.span.end as usize,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            Statement::ExportNamedDeclaration(decl) => {
                if let Some(declaration) = &decl.declaration {
                    collect_declaration(
                        declaration,
                        true,
                        &source,
                        response.props.as_mut(),
                        &mut response.bindings,
                    );
                }
            }
            _ => {}
        }

        if let Some(declaration) = statement.as_declaration() {
            collect_declaration(
                declaration,
                false,
                &source,
                response.props.as_mut(),
                &mut response.bindings,
            );
        }
    }

    if let Some(props) = response.props.as_ref() {
        if !props.has_props_export {
            response.diagnostics.push(DiagnosticRecord {
                severity: "error".to_string(),
                message: "Missing `export let props: Props` declaration".to_string(),
                span_start: 0,
                span_end: 0,
                line: 0,
                column: 0,
                code: None,
            });
        } else if props.props_type_name.is_none() {
            response.diagnostics.push(DiagnosticRecord {
                severity: "error".to_string(),
                message: "Props export is missing a type annotation".to_string(),
                span_start: 0,
                span_end: 0,
                line: 0,
                column: 0,
                code: None,
            });
        }
    }

    response.state_analysis = analyze_state(&parsed.program, &source, &response.bindings);

    to_json_ptr(&response)
}

#[no_mangle]
pub extern "C" fn weiv_backend_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub extern "C" fn weiv_transpile_module(
    source: *const c_char,
    source_path: *const c_char,
) -> *mut c_char {
    let source = match parse_required_cstr(source) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let source_path = parse_optional_cstr(source_path).unwrap_or_else(|| "<module>".to_string());

    match transpile_source(&source, &source_path).and_then(|code| CString::new(code).ok()) {
        Some(value) => value.into_raw(),
        None => std::ptr::null_mut(),
    }
}

fn to_json_ptr<T: Serialize>(value: &T) -> *mut c_char {
    match serde_json::to_string(value)
        .ok()
        .and_then(|json| CString::new(json).ok())
    {
        Some(value) => value.into_raw(),
        None => std::ptr::null_mut(),
    }
}

fn parse_required_cstr(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok().map(ToOwned::to_owned) }
}

fn parse_optional_cstr(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(value).to_str().ok().map(ToOwned::to_owned) }
}

fn collect_declaration(
    declaration: &Declaration<'_>,
    exported: bool,
    source: &str,
    mut props: Option<&mut PropsRecord>,
    bindings: &mut Vec<BindingRecord>,
) {
    match declaration {
        Declaration::VariableDeclaration(decl) => {
            for declarator in &decl.declarations {
                let kind = match decl.kind {
                    VariableDeclarationKind::Const => "immutable",
                    _ => "mutable",
                };
                let type_annotation = declarator.type_annotation.as_ref().map(|annotation| {
                    annotation
                        .span
                        .source_text(source)
                        .trim_start_matches(':')
                        .trim()
                        .to_string()
                });

                let mut names = Vec::new();
                collect_binding_names(&declarator.id, &mut names);
                for (name, span_start, span_end) in names {
                    if exported && name == "props" {
                        if let Some(props_record) = props.as_deref_mut() {
                            props_record.has_props_export = true;
                            props_record.props_binding_name = Some(name.clone());
                            props_record.props_type_name = type_annotation.clone();
                        }
                    }
                    bindings.push(BindingRecord {
                        name,
                        kind: kind.to_string(),
                        exported,
                        template_visible: true,
                        callable: false,
                        type_annotation: type_annotation.clone(),
                        span_start,
                        span_end,
                    });
                }
            }
        }
        Declaration::FunctionDeclaration(function) => {
            if let Some(id) = &function.id {
                bindings.push(BindingRecord {
                    name: id.name.as_str().to_string(),
                    kind: "function".to_string(),
                    exported,
                    template_visible: true,
                    callable: true,
                    type_annotation: None,
                    span_start: id.span.start as usize,
                    span_end: id.span.end as usize,
                });
            }
        }
        Declaration::TSInterfaceDeclaration(interface) => {
            bindings.push(BindingRecord {
                name: interface.id.name.as_str().to_string(),
                kind: "type_only".to_string(),
                exported,
                template_visible: false,
                callable: false,
                type_annotation: None,
                span_start: interface.id.span.start as usize,
                span_end: interface.id.span.end as usize,
            });
        }
        Declaration::TSTypeAliasDeclaration(alias) => {
            bindings.push(BindingRecord {
                name: alias.id.name.as_str().to_string(),
                kind: "type_only".to_string(),
                exported,
                template_visible: false,
                callable: false,
                type_annotation: None,
                span_start: alias.id.span.start as usize,
                span_end: alias.id.span.end as usize,
            });
        }
        _ => {}
    }
}

fn collect_binding_names(pattern: &BindingPattern<'_>, out: &mut Vec<(String, usize, usize)>) {
    match pattern {
        BindingPattern::BindingIdentifier(id) => {
            out.push((
                id.name.as_str().to_string(),
                id.span.start as usize,
                id.span.end as usize,
            ));
        }
        BindingPattern::AssignmentPattern(assign) => {
            collect_binding_names(&assign.left, out);
        }
        BindingPattern::ObjectPattern(object) => {
            for property in &object.properties {
                collect_binding_names(&property.value, out);
            }
            if let Some(rest) = &object.rest {
                collect_binding_names(&rest.argument, out);
            }
        }
        BindingPattern::ArrayPattern(array) => {
            for element in &array.elements {
                if let Some(element) = element {
                    collect_binding_names(element, out);
                }
            }
            if let Some(rest) = &array.rest {
                collect_binding_names(&rest.argument, out);
            }
        }
    }
}

fn analyze_state(
    program: &Program<'_>,
    source: &str,
    bindings: &[BindingRecord],
) -> StateAnalysisRecord {
    let top_level_bindings: BTreeSet<String> = bindings
        .iter()
        .filter(|binding| binding.template_visible)
        .map(|binding| binding.name.clone())
        .collect();

    let mut state = StateAnalysisRecord::default();
    for statement in &program.body {
        collect_state_from_statement(
            statement,
            source,
            &top_level_bindings,
            &mut state,
            TraversalContext::default(),
        );
    }
    state
}

#[derive(Clone, Copy, Default)]
struct TraversalContext {
    inside_callback: bool,
    callback_owned_candidate: bool,
    statement_position: bool,
}

impl TraversalContext {
    fn nested(self) -> Self {
        Self {
            statement_position: false,
            ..self
        }
    }

    fn for_statement_expression(self) -> Self {
        Self {
            statement_position: true,
            ..self
        }
    }

    fn inside_callback(self, owned_candidate: bool) -> Self {
        Self {
            inside_callback: true,
            callback_owned_candidate: owned_candidate,
            statement_position: false,
        }
    }
}

#[derive(Default)]
struct HelperAnalysis {
    reads: BTreeSet<String>,
    writes: BTreeSet<String>,
    calls: BTreeSet<String>,
    contains_external_reads: bool,
    contains_side_effects: bool,
}

fn collect_state_from_statement(
    statement: &Statement<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    state: &mut StateAnalysisRecord,
    context: TraversalContext,
) {
    match statement {
        Statement::BlockStatement(block) => {
            for stmt in &block.body {
                collect_state_from_statement(stmt, source, top_level_bindings, state, context);
            }
        }
        Statement::ExpressionStatement(expr_stmt) => {
            collect_state_from_expression(
                &expr_stmt.expression,
                source,
                top_level_bindings,
                state,
                context.for_statement_expression(),
            );
        }
        Statement::IfStatement(if_stmt) => {
            collect_state_from_expression(
                &if_stmt.test,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_statement(
                &if_stmt.consequent,
                source,
                top_level_bindings,
                state,
                context,
            );
            if let Some(alternate) = &if_stmt.alternate {
                collect_state_from_statement(alternate, source, top_level_bindings, state, context);
            }
        }
        Statement::ReturnStatement(return_stmt) => {
            if let Some(argument) = &return_stmt.argument {
                collect_state_from_expression(argument, source, top_level_bindings, state, context);
            }
        }
        Statement::VariableDeclaration(decl) => {
            collect_aliases_from_declaration(decl, source, top_level_bindings, state);
            for declarator in &decl.declarations {
                if let Some(init) = &declarator.init {
                    collect_state_from_expression(init, source, top_level_bindings, state, context);
                }
            }
        }
        Statement::FunctionDeclaration(function) => {
            if let Some(id) = &function.id {
                state.helpers.push(analyze_function_like(
                    id.name.as_str().to_string(),
                    "function",
                    function.span.start as usize,
                    function.span.end as usize,
                    function.body.as_deref(),
                    function.r#async,
                    false,
                    function.params.as_ref(),
                    source,
                    top_level_bindings,
                ));
            }
            if let Some(body) = &function.body {
                for stmt in &body.statements {
                    collect_state_from_statement(stmt, source, top_level_bindings, state, context);
                }
            }
        }
        Statement::ForStatement(for_stmt) => {
            if let Some(init) = &for_stmt.init {
                match init {
                    ForStatementInit::VariableDeclaration(decl) => {
                        collect_aliases_from_declaration(decl, source, top_level_bindings, state);
                        for declarator in &decl.declarations {
                            if let Some(init) = &declarator.init {
                                collect_state_from_expression(
                                    init,
                                    source,
                                    top_level_bindings,
                                    state,
                                    context,
                                );
                            }
                        }
                    }
                    _ => collect_state_from_expression(
                        init.to_expression(),
                        source,
                        top_level_bindings,
                        state,
                        context.for_statement_expression(),
                    ),
                }
            }
            if let Some(test) = &for_stmt.test {
                collect_state_from_expression(test, source, top_level_bindings, state, context);
            }
            if let Some(update) = &for_stmt.update {
                collect_state_from_expression(update, source, top_level_bindings, state, context);
            }
            collect_state_from_statement(
                &for_stmt.body,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        Statement::WhileStatement(while_stmt) => {
            collect_state_from_expression(
                &while_stmt.test,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_statement(
                &while_stmt.body,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        Statement::DoWhileStatement(do_while_stmt) => {
            collect_state_from_statement(
                &do_while_stmt.body,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_expression(
                &do_while_stmt.test,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        Statement::ForInStatement(for_in_stmt) => {
            collect_state_from_expression(
                &for_in_stmt.right,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_statement(
                &for_in_stmt.body,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        Statement::ForOfStatement(for_of_stmt) => {
            collect_state_from_expression(
                &for_of_stmt.right,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_statement(
                &for_of_stmt.body,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        Statement::SwitchStatement(switch_stmt) => {
            collect_state_from_expression(
                &switch_stmt.discriminant,
                source,
                top_level_bindings,
                state,
                context,
            );
            for case in &switch_stmt.cases {
                if let Some(test) = &case.test {
                    collect_state_from_expression(test, source, top_level_bindings, state, context);
                }
                for stmt in &case.consequent {
                    collect_state_from_statement(stmt, source, top_level_bindings, state, context);
                }
            }
        }
        Statement::TryStatement(try_stmt) => {
            for stmt in &try_stmt.block.body {
                collect_state_from_statement(stmt, source, top_level_bindings, state, context);
            }
            if let Some(handler) = &try_stmt.handler {
                for stmt in &handler.body.body {
                    collect_state_from_statement(stmt, source, top_level_bindings, state, context);
                }
            }
            if let Some(finalizer) = &try_stmt.finalizer {
                for stmt in &finalizer.body {
                    collect_state_from_statement(stmt, source, top_level_bindings, state, context);
                }
            }
        }
        _ => {}
    }
}

fn collect_aliases_from_declaration(
    decl: &VariableDeclaration<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    state: &mut StateAnalysisRecord,
) {
    for declarator in &decl.declarations {
        let Some(Expression::Identifier(target)) = &declarator.init else {
            continue;
        };
        let BindingPattern::BindingIdentifier(alias) = &declarator.id else {
            continue;
        };
        let target_name = target.name.as_str().to_string();
        if !top_level_bindings.contains(&target_name) {
            continue;
        }
        state.aliases.push(AliasRecord {
            alias: alias.name.as_str().to_string(),
            target: target_name,
            kind: "direct_binding_alias".to_string(),
            span_start: declarator.span.start as usize,
            span_end: declarator.span.end as usize,
        });
        let _ = source;
    }
}

fn analyze_function_like(
    name: String,
    kind: &str,
    span_start: usize,
    span_end: usize,
    body: Option<&FunctionBody<'_>>,
    async_flag: bool,
    returns_expression_only: bool,
    params: &FormalParameters<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
) -> HelperRecord {
    let mut analysis = HelperAnalysis::default();
    let mut locals = BTreeSet::new();
    collect_formal_param_names(params, &mut locals);

    if let Some(body) = body {
        for stmt in &body.statements {
            analyze_helper_statement(stmt, source, top_level_bindings, &mut locals, &mut analysis);
        }
    }

    HelperRecord {
        name,
        kind: kind.to_string(),
        span_start,
        span_end,
        reads: analysis.reads.into_iter().collect(),
        writes: analysis.writes.into_iter().collect(),
        calls: analysis.calls.into_iter().collect(),
        async_flag,
        returns_expression_only,
        contains_external_reads: analysis.contains_external_reads,
        contains_side_effects: analysis.contains_side_effects,
    }
}

fn analyze_helper_statement(
    statement: &Statement<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    locals: &mut BTreeSet<String>,
    analysis: &mut HelperAnalysis,
) {
    match statement {
        Statement::ExpressionStatement(expr_stmt) => {
            analyze_helper_expression(
                &expr_stmt.expression,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Statement::ReturnStatement(return_stmt) => {
            if let Some(argument) = &return_stmt.argument {
                analyze_helper_expression(argument, source, top_level_bindings, locals, analysis);
            }
        }
        Statement::IfStatement(if_stmt) => {
            analyze_helper_expression(&if_stmt.test, source, top_level_bindings, locals, analysis);
            analyze_helper_statement(
                &if_stmt.consequent,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
            if let Some(alternate) = &if_stmt.alternate {
                analyze_helper_statement(alternate, source, top_level_bindings, locals, analysis);
            }
        }
        Statement::BlockStatement(block) => {
            for stmt in &block.body {
                analyze_helper_statement(stmt, source, top_level_bindings, locals, analysis);
            }
        }
        Statement::VariableDeclaration(decl) => {
            for declarator in &decl.declarations {
                collect_binding_pattern_names_only(&declarator.id, locals);
                if let Some(init) = &declarator.init {
                    analyze_helper_expression(init, source, top_level_bindings, locals, analysis);
                }
            }
        }
        Statement::ForStatement(for_stmt) => {
            if let Some(init) = &for_stmt.init {
                match init {
                    ForStatementInit::VariableDeclaration(decl) => {
                        for declarator in &decl.declarations {
                            collect_binding_pattern_names_only(&declarator.id, locals);
                            if let Some(init) = &declarator.init {
                                analyze_helper_expression(
                                    init,
                                    source,
                                    top_level_bindings,
                                    locals,
                                    analysis,
                                );
                            }
                        }
                    }
                    _ => analyze_helper_expression(
                        init.to_expression(),
                        source,
                        top_level_bindings,
                        locals,
                        analysis,
                    ),
                }
            }
            if let Some(test) = &for_stmt.test {
                analyze_helper_expression(test, source, top_level_bindings, locals, analysis);
            }
            if let Some(update) = &for_stmt.update {
                analyze_helper_expression(update, source, top_level_bindings, locals, analysis);
            }
            analyze_helper_statement(&for_stmt.body, source, top_level_bindings, locals, analysis);
        }
        Statement::WhileStatement(while_stmt) => {
            analyze_helper_expression(
                &while_stmt.test,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
            analyze_helper_statement(
                &while_stmt.body,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Statement::DoWhileStatement(do_while_stmt) => {
            analyze_helper_statement(
                &do_while_stmt.body,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
            analyze_helper_expression(
                &do_while_stmt.test,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Statement::SwitchStatement(switch_stmt) => {
            analyze_helper_expression(
                &switch_stmt.discriminant,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
            for case in &switch_stmt.cases {
                if let Some(test) = &case.test {
                    analyze_helper_expression(test, source, top_level_bindings, locals, analysis);
                }
                for stmt in &case.consequent {
                    analyze_helper_statement(stmt, source, top_level_bindings, locals, analysis);
                }
            }
        }
        _ => {}
    }
}

fn analyze_helper_expression(
    expression: &Expression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    locals: &BTreeSet<String>,
    analysis: &mut HelperAnalysis,
) {
    match expression {
        Expression::Identifier(id) => {
            let name = id.name.as_str().to_string();
            if locals.contains(&name) {
                return;
            }
            if top_level_bindings.contains(&name) {
                analysis.reads.insert(name);
            } else {
                analysis.contains_external_reads = true;
            }
        }
        Expression::AssignmentExpression(assign) => {
            analysis.contains_side_effects = true;
            if let Some((binding, member_path)) = assignment_target_binding(&assign.left, source) {
                analysis.writes.insert(binding.clone());
                if !top_level_bindings.contains(&binding) {
                    analysis.contains_external_reads = true;
                }
                let _ = member_path;
            }
            analyze_helper_expression(&assign.right, source, top_level_bindings, locals, analysis);
        }
        Expression::UpdateExpression(update) => {
            analysis.contains_side_effects = true;
            if let Some(binding) = simple_assignment_target_binding(&update.argument, source)
                .map(|(binding, _)| binding)
            {
                analysis.writes.insert(binding);
            }
        }
        Expression::CallExpression(call) => {
            analyze_helper_call_expression(call, source, top_level_bindings, locals, analysis);
        }
        Expression::StaticMemberExpression(member) => {
            analyze_helper_expression(&member.object, source, top_level_bindings, locals, analysis);
        }
        Expression::ComputedMemberExpression(member) => {
            analyze_helper_expression(&member.object, source, top_level_bindings, locals, analysis);
            analyze_helper_expression(
                &member.expression,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Expression::ChainExpression(chain) => {
            analyze_chain_expression(chain, source, top_level_bindings, locals, analysis);
        }
        Expression::BinaryExpression(binary) => {
            analyze_helper_expression(&binary.left, source, top_level_bindings, locals, analysis);
            analyze_helper_expression(&binary.right, source, top_level_bindings, locals, analysis);
        }
        Expression::LogicalExpression(logical) => {
            analyze_helper_expression(&logical.left, source, top_level_bindings, locals, analysis);
            analyze_helper_expression(&logical.right, source, top_level_bindings, locals, analysis);
        }
        Expression::ConditionalExpression(cond) => {
            analyze_helper_expression(&cond.test, source, top_level_bindings, locals, analysis);
            analyze_helper_expression(
                &cond.consequent,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
            analyze_helper_expression(
                &cond.alternate,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Expression::UnaryExpression(unary) => {
            analyze_helper_expression(
                &unary.argument,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Expression::AwaitExpression(await_expr) => {
            analysis.contains_side_effects = true;
            analyze_helper_expression(
                &await_expr.argument,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Expression::ArrayExpression(array) => {
            for element in &array.elements {
                if let Some(expr) = array_expression_element(element) {
                    analyze_helper_expression(expr, source, top_level_bindings, locals, analysis);
                }
            }
        }
        Expression::ObjectExpression(object) => {
            for property in &object.properties {
                match property {
                    ObjectPropertyKind::ObjectProperty(prop) => {
                        analyze_helper_expression(
                            &prop.value,
                            source,
                            top_level_bindings,
                            locals,
                            analysis,
                        );
                    }
                    ObjectPropertyKind::SpreadProperty(spread) => {
                        analyze_helper_expression(
                            &spread.argument,
                            source,
                            top_level_bindings,
                            locals,
                            analysis,
                        );
                    }
                }
            }
        }
        Expression::TemplateLiteral(template) => {
            for expr in &template.expressions {
                analyze_helper_expression(expr, source, top_level_bindings, locals, analysis);
            }
        }
        Expression::ParenthesizedExpression(paren) => {
            analyze_helper_expression(
                &paren.expression,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        Expression::SequenceExpression(seq) => {
            for expr in &seq.expressions {
                analyze_helper_expression(expr, source, top_level_bindings, locals, analysis);
            }
        }
        Expression::ArrowFunctionExpression(callback) => {
            let mut callback_locals = locals.clone();
            collect_formal_param_names(&callback.params, &mut callback_locals);
            if callback.expression {
                if let Some(Statement::ExpressionStatement(stmt)) = callback.body.statements.first()
                {
                    analyze_helper_expression(
                        &stmt.expression,
                        source,
                        top_level_bindings,
                        &callback_locals,
                        analysis,
                    );
                }
            } else {
                for stmt in &callback.body.statements {
                    analyze_helper_statement(
                        stmt,
                        source,
                        top_level_bindings,
                        &mut callback_locals,
                        analysis,
                    );
                }
            }
        }
        Expression::FunctionExpression(callback) => {
            let mut callback_locals = locals.clone();
            collect_formal_param_names(&callback.params, &mut callback_locals);
            if let Some(id) = &callback.id {
                callback_locals.insert(id.name.as_str().to_string());
            }
            if let Some(body) = &callback.body {
                for stmt in &body.statements {
                    analyze_helper_statement(
                        stmt,
                        source,
                        top_level_bindings,
                        &mut callback_locals,
                        analysis,
                    );
                }
            }
        }
        _ => {}
    }
}

fn collect_state_from_expression(
    expression: &Expression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    state: &mut StateAnalysisRecord,
    context: TraversalContext,
) {
    match expression {
        Expression::AssignmentExpression(assign) => {
            if let Some((binding, member_path)) = assignment_target_binding(&assign.left, source) {
                state.mutations.push(MutationRecord {
                    binding,
                    kind: if member_path.is_some() {
                        "member-assignment".to_string()
                    } else {
                        "assignment".to_string()
                    },
                    span_start: assign.span.start as usize,
                    span_end: assign.span.end as usize,
                    statement_position: context.statement_position,
                    member_path,
                    inside_callback: context.inside_callback,
                    callback_owned_candidate: context.callback_owned_candidate,
                });
            }
            collect_state_from_expression(
                &assign.right,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::UpdateExpression(update) => {
            if let Some((binding, member_path)) =
                simple_assignment_target_binding(&update.argument, source)
            {
                state.mutations.push(MutationRecord {
                    binding,
                    kind: "update".to_string(),
                    span_start: update.span.start as usize,
                    span_end: update.span.end as usize,
                    statement_position: context.statement_position,
                    member_path,
                    inside_callback: context.inside_callback,
                    callback_owned_candidate: context.callback_owned_candidate,
                });
            }
        }
        Expression::CallExpression(call) => {
            collect_state_from_call_expression(call, source, top_level_bindings, state, context);
        }
        Expression::StaticMemberExpression(member) => {
            collect_state_from_expression(
                &member.object,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::ComputedMemberExpression(member) => {
            collect_state_from_expression(
                &member.object,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
            collect_state_from_expression(
                &member.expression,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::ChainExpression(chain) => {
            collect_state_from_chain_expression(chain, source, top_level_bindings, state, context);
        }
        Expression::BinaryExpression(binary) => {
            collect_state_from_expression(
                &binary.left,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
            collect_state_from_expression(
                &binary.right,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::LogicalExpression(logical) => {
            collect_state_from_expression(
                &logical.left,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
            collect_state_from_expression(
                &logical.right,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::ConditionalExpression(cond) => {
            collect_state_from_expression(
                &cond.test,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
            collect_state_from_expression(
                &cond.consequent,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
            collect_state_from_expression(
                &cond.alternate,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::UnaryExpression(unary) => {
            collect_state_from_expression(
                &unary.argument,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::AwaitExpression(await_expr) => {
            collect_state_from_expression(
                &await_expr.argument,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::ArrayExpression(array) => {
            for element in &array.elements {
                if let Some(expr) = array_expression_element(element) {
                    collect_state_from_expression(
                        expr,
                        source,
                        top_level_bindings,
                        state,
                        context.nested(),
                    );
                }
            }
        }
        Expression::ObjectExpression(object) => {
            for property in &object.properties {
                match property {
                    ObjectPropertyKind::ObjectProperty(prop) => {
                        collect_state_from_expression(
                            &prop.value,
                            source,
                            top_level_bindings,
                            state,
                            context.nested(),
                        );
                    }
                    ObjectPropertyKind::SpreadProperty(spread) => {
                        collect_state_from_expression(
                            &spread.argument,
                            source,
                            top_level_bindings,
                            state,
                            context.nested(),
                        );
                    }
                }
            }
        }
        Expression::TemplateLiteral(template) => {
            for expr in &template.expressions {
                collect_state_from_expression(
                    expr,
                    source,
                    top_level_bindings,
                    state,
                    context.nested(),
                );
            }
        }
        Expression::ParenthesizedExpression(paren) => {
            collect_state_from_expression(
                &paren.expression,
                source,
                top_level_bindings,
                state,
                context.nested(),
            );
        }
        Expression::SequenceExpression(seq) => {
            for expr in &seq.expressions {
                collect_state_from_expression(
                    expr,
                    source,
                    top_level_bindings,
                    state,
                    context.nested(),
                );
            }
        }
        Expression::ArrowFunctionExpression(callback) => {
            let owned_candidate = false;
            state
                .callback_registrations
                .push(CallbackRegistrationRecord {
                    callee: "<inline>".to_string(),
                    callback_kind: "arrow".to_string(),
                    callback_span_start: callback.span.start as usize,
                    callback_span_end: callback.span.end as usize,
                    owned_candidate,
                    reason: "inline_function_value".to_string(),
                });
            if callback.expression {
                if let Some(Statement::ExpressionStatement(stmt)) = callback.body.statements.first()
                {
                    collect_state_from_expression(
                        &stmt.expression,
                        source,
                        top_level_bindings,
                        state,
                        context.inside_callback(owned_candidate),
                    );
                }
            } else {
                for stmt in &callback.body.statements {
                    collect_state_from_statement(
                        stmt,
                        source,
                        top_level_bindings,
                        state,
                        context.inside_callback(owned_candidate),
                    );
                }
            }
        }
        Expression::FunctionExpression(callback) => {
            let owned_candidate = false;
            state
                .callback_registrations
                .push(CallbackRegistrationRecord {
                    callee: "<inline>".to_string(),
                    callback_kind: "function".to_string(),
                    callback_span_start: callback.span.start as usize,
                    callback_span_end: callback.span.end as usize,
                    owned_candidate,
                    reason: "inline_function_value".to_string(),
                });
            if let Some(body) = &callback.body {
                for stmt in &body.statements {
                    collect_state_from_statement(
                        stmt,
                        source,
                        top_level_bindings,
                        state,
                        context.inside_callback(owned_candidate),
                    );
                }
            }
        }
        _ => {}
    }
}

fn collect_formal_param_names(params: &FormalParameters<'_>, out: &mut BTreeSet<String>) {
    for item in &params.items {
        collect_binding_pattern_names_only(&item.pattern, out);
    }
    if let Some(rest) = &params.rest {
        collect_binding_pattern_names_only(&rest.rest.argument, out);
    }
}

fn analyze_helper_call_expression(
    call: &CallExpression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    locals: &BTreeSet<String>,
    analysis: &mut HelperAnalysis,
) {
    analyze_helper_expression(&call.callee, source, top_level_bindings, locals, analysis);
    if let Some(callee_name) = callee_name(&call.callee, source) {
        analysis.calls.insert(callee_name.clone());
        if is_known_mutating_call_name(&callee_name) {
            analysis.contains_side_effects = true;
        }
    } else {
        analysis.contains_side_effects = true;
    }
    for arg in &call.arguments {
        match arg {
            Argument::ArrowFunctionExpression(callback) => {
                let mut callback_locals = locals.clone();
                collect_formal_param_names(&callback.params, &mut callback_locals);
                if callback.expression {
                    if let Some(Statement::ExpressionStatement(stmt)) =
                        callback.body.statements.first()
                    {
                        analyze_helper_expression(
                            &stmt.expression,
                            source,
                            top_level_bindings,
                            &callback_locals,
                            analysis,
                        );
                    }
                } else {
                    for stmt in &callback.body.statements {
                        analyze_helper_statement(
                            stmt,
                            source,
                            top_level_bindings,
                            &mut callback_locals,
                            analysis,
                        );
                    }
                }
            }
            Argument::FunctionExpression(callback) => {
                let mut callback_locals = locals.clone();
                collect_formal_param_names(&callback.params, &mut callback_locals);
                if let Some(id) = &callback.id {
                    callback_locals.insert(id.name.as_str().to_string());
                }
                if let Some(body) = &callback.body {
                    for stmt in &body.statements {
                        analyze_helper_statement(
                            stmt,
                            source,
                            top_level_bindings,
                            &mut callback_locals,
                            analysis,
                        );
                    }
                }
            }
            _ => {
                if let Some(expr) = argument_expression(arg) {
                    analyze_helper_expression(expr, source, top_level_bindings, locals, analysis);
                }
            }
        }
    }
}

fn collect_state_from_call_expression(
    call: &CallExpression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    state: &mut StateAnalysisRecord,
    context: TraversalContext,
) {
    if let Some(callee_name) = callee_name(&call.callee, source) {
        if let Some((binding, member_path)) = mutation_from_call(&callee_name) {
            state.mutations.push(MutationRecord {
                binding,
                kind: "method".to_string(),
                span_start: call.span.start as usize,
                span_end: call.span.end as usize,
                statement_position: context.statement_position,
                member_path: Some(member_path),
                inside_callback: context.inside_callback,
                callback_owned_candidate: context.callback_owned_candidate,
            });
        }
    }

    for arg in &call.arguments {
        match arg {
            Argument::ArrowFunctionExpression(callback) => {
                let owned_candidate = is_owned_callback_callee(&call.callee, source);
                state
                    .callback_registrations
                    .push(CallbackRegistrationRecord {
                        callee: callee_name(&call.callee, source)
                            .unwrap_or_else(|| call.callee.span().source_text(source).to_string()),
                        callback_kind: "inline_arrow".to_string(),
                        callback_span_start: callback.span.start as usize,
                        callback_span_end: callback.span.end as usize,
                        owned_candidate,
                        reason: if owned_candidate {
                            "known_owned_boundary".to_string()
                        } else {
                            "unknown_registration".to_string()
                        },
                    });
                if callback.expression {
                    if let Some(Statement::ExpressionStatement(stmt)) =
                        callback.body.statements.first()
                    {
                        collect_state_from_expression(
                            &stmt.expression,
                            source,
                            top_level_bindings,
                            state,
                            context.inside_callback(owned_candidate),
                        );
                    }
                } else {
                    for stmt in &callback.body.statements {
                        collect_state_from_statement(
                            stmt,
                            source,
                            top_level_bindings,
                            state,
                            context.inside_callback(owned_candidate),
                        );
                    }
                }
            }
            Argument::FunctionExpression(callback) => {
                let owned_candidate = is_owned_callback_callee(&call.callee, source);
                state
                    .callback_registrations
                    .push(CallbackRegistrationRecord {
                        callee: callee_name(&call.callee, source)
                            .unwrap_or_else(|| call.callee.span().source_text(source).to_string()),
                        callback_kind: "inline_function".to_string(),
                        callback_span_start: callback.span.start as usize,
                        callback_span_end: callback.span.end as usize,
                        owned_candidate,
                        reason: if owned_candidate {
                            "known_owned_boundary".to_string()
                        } else {
                            "unknown_registration".to_string()
                        },
                    });
                if let Some(body) = &callback.body {
                    for stmt in &body.statements {
                        collect_state_from_statement(
                            stmt,
                            source,
                            top_level_bindings,
                            state,
                            context.inside_callback(owned_candidate),
                        );
                    }
                }
            }
            _ => {
                if let Some(expr) = argument_expression(arg) {
                    collect_state_from_expression(
                        expr,
                        source,
                        top_level_bindings,
                        state,
                        context.nested(),
                    );
                }
            }
        }
    }
}

fn collect_binding_pattern_names_only(pattern: &BindingPattern<'_>, out: &mut BTreeSet<String>) {
    match pattern {
        BindingPattern::BindingIdentifier(id) => {
            out.insert(id.name.as_str().to_string());
        }
        BindingPattern::AssignmentPattern(assign) => {
            collect_binding_pattern_names_only(&assign.left, out);
        }
        BindingPattern::ObjectPattern(object) => {
            for property in &object.properties {
                collect_binding_pattern_names_only(&property.value, out);
            }
            if let Some(rest) = &object.rest {
                collect_binding_pattern_names_only(&rest.argument, out);
            }
        }
        BindingPattern::ArrayPattern(array) => {
            for element in &array.elements {
                if let Some(element) = element {
                    collect_binding_pattern_names_only(element, out);
                }
            }
            if let Some(rest) = &array.rest {
                collect_binding_pattern_names_only(&rest.argument, out);
            }
        }
    }
}

fn argument_expression<'a>(arg: &'a Argument<'a>) -> Option<&'a Expression<'a>> {
    match arg {
        Argument::SpreadElement(spread) => Some(&spread.argument),
        _ => arg.as_expression(),
    }
}

fn array_expression_element<'a>(
    element: &'a ArrayExpressionElement<'a>,
) -> Option<&'a Expression<'a>> {
    match element {
        ArrayExpressionElement::SpreadElement(spread) => Some(&spread.argument),
        _ => element.as_expression(),
    }
}

fn collect_state_from_chain_expression(
    chain: &ChainExpression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    state: &mut StateAnalysisRecord,
    context: TraversalContext,
) {
    match &chain.expression {
        ChainElement::CallExpression(call) => {
            collect_state_from_call_expression(call, source, top_level_bindings, state, context)
        }
        ChainElement::ComputedMemberExpression(member) => {
            collect_state_from_expression(
                &member.object,
                source,
                top_level_bindings,
                state,
                context,
            );
            collect_state_from_expression(
                &member.expression,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        ChainElement::StaticMemberExpression(member) => {
            collect_state_from_expression(
                &member.object,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        ChainElement::PrivateFieldExpression(member) => {
            collect_state_from_expression(
                &member.object,
                source,
                top_level_bindings,
                state,
                context,
            );
        }
        _ => {}
    }
}

fn analyze_chain_expression(
    chain: &ChainExpression<'_>,
    source: &str,
    top_level_bindings: &BTreeSet<String>,
    locals: &BTreeSet<String>,
    analysis: &mut HelperAnalysis,
) {
    match &chain.expression {
        ChainElement::CallExpression(call) => {
            analyze_helper_call_expression(call, source, top_level_bindings, locals, analysis)
        }
        ChainElement::ComputedMemberExpression(member) => {
            analyze_helper_expression(&member.object, source, top_level_bindings, locals, analysis);
            analyze_helper_expression(
                &member.expression,
                source,
                top_level_bindings,
                locals,
                analysis,
            );
        }
        ChainElement::StaticMemberExpression(member) => {
            analyze_helper_expression(&member.object, source, top_level_bindings, locals, analysis);
        }
        ChainElement::PrivateFieldExpression(member) => {
            analyze_helper_expression(&member.object, source, top_level_bindings, locals, analysis);
        }
        _ => {}
    }
}

fn assignment_target_binding(
    target: &AssignmentTarget<'_>,
    source: &str,
) -> Option<(String, Option<String>)> {
    match target {
        AssignmentTarget::AssignmentTargetIdentifier(id) => {
            Some((id.name.as_str().to_string(), None))
        }
        AssignmentTarget::ComputedMemberExpression(member) => member_expression_binding(
            &member.object,
            Some(member.expression.span().source_text(source).to_string()),
            source,
        ),
        AssignmentTarget::StaticMemberExpression(member) => member_expression_binding(
            &member.object,
            Some(member.property.name.as_str().to_string()),
            source,
        ),
        AssignmentTarget::PrivateFieldExpression(member) => member_expression_binding(
            &member.object,
            Some(member.field.name.as_str().to_string()),
            source,
        ),
        AssignmentTarget::TSAsExpression(_) => None,
        AssignmentTarget::TSSatisfiesExpression(_) => None,
        AssignmentTarget::TSNonNullExpression(_) => None,
        AssignmentTarget::TSTypeAssertion(_) => None,
        _ => None,
    }
}

fn simple_assignment_target_binding(
    target: &SimpleAssignmentTarget<'_>,
    source: &str,
) -> Option<(String, Option<String>)> {
    match target {
        SimpleAssignmentTarget::AssignmentTargetIdentifier(id) => {
            Some((id.name.as_str().to_string(), None))
        }
        SimpleAssignmentTarget::ComputedMemberExpression(member) => member_expression_binding(
            &member.object,
            Some(member.expression.span().source_text(source).to_string()),
            source,
        ),
        SimpleAssignmentTarget::StaticMemberExpression(member) => member_expression_binding(
            &member.object,
            Some(member.property.name.as_str().to_string()),
            source,
        ),
        SimpleAssignmentTarget::PrivateFieldExpression(member) => member_expression_binding(
            &member.object,
            Some(member.field.name.as_str().to_string()),
            source,
        ),
        _ => None,
    }
}

fn member_expression_binding(
    object: &Expression<'_>,
    member: Option<String>,
    source: &str,
) -> Option<(String, Option<String>)> {
    match object {
        Expression::Identifier(id) => Some((id.name.as_str().to_string(), member)),
        Expression::StaticMemberExpression(parent) => {
            let (binding, path) = member_expression_binding(
                &parent.object,
                Some(parent.property.name.as_str().to_string()),
                source,
            )?;
            Some((binding, path.or(member)))
        }
        Expression::ComputedMemberExpression(parent) => {
            let (binding, path) = member_expression_binding(
                &parent.object,
                Some(parent.expression.span().source_text(source).to_string()),
                source,
            )?;
            Some((binding, path.or(member)))
        }
        _ => None,
    }
}

fn callee_name(callee: &Expression<'_>, source: &str) -> Option<String> {
    match callee {
        Expression::Identifier(id) => Some(id.name.as_str().to_string()),
        Expression::StaticMemberExpression(member) => {
            let object = callee_name(&member.object, source)?;
            Some(format!("{object}.{}", member.property.name.as_str()))
        }
        Expression::ComputedMemberExpression(member) => {
            let object = callee_name(&member.object, source)?;
            Some(format!(
                "{object}[{}]",
                member.expression.span().source_text(source)
            ))
        }
        _ => Some(callee.span().source_text(source).to_string()),
    }
}

fn mutation_from_call(callee_name: &str) -> Option<(String, String)> {
    for method in [
        ".push",
        ".pop",
        ".shift",
        ".unshift",
        ".splice",
        ".sort",
        ".reverse",
        ".copyWithin",
        ".fill",
        ".set",
        ".delete",
        ".clear",
        ".add",
    ] {
        if let Some(binding) = callee_name.strip_suffix(method) {
            return Some((
                binding.to_string(),
                method.trim_start_matches('.').to_string(),
            ));
        }
    }
    None
}

fn is_known_mutating_call_name(callee_name: &str) -> bool {
    mutation_from_call(callee_name).is_some()
}

fn is_owned_callback_callee(callee: &Expression<'_>, source: &str) -> bool {
    match callee_name(callee, source).as_deref() {
        Some("setTimeout")
        | Some("setInterval")
        | Some("queueMicrotask")
        | Some("requestAnimationFrame") => true,
        _ => false,
    }
}

fn module_export_name(name: &oxc_ast::ast::ModuleExportName<'_>) -> String {
    match name {
        oxc_ast::ast::ModuleExportName::IdentifierName(it) => it.name.as_str().to_string(),
        oxc_ast::ast::ModuleExportName::IdentifierReference(it) => it.name.as_str().to_string(),
        oxc_ast::ast::ModuleExportName::StringLiteral(it) => it.value.as_str().to_string(),
    }
}

#[no_mangle]
pub extern "C" fn weiv_rewrite_expression(
    expression: *const c_char,
    scope_bindings_json: *const c_char,
    scope_prefix: *const c_char,
) -> *mut c_char {
    let expression = match parse_required_cstr(expression) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let scope_bindings_json = match parse_required_cstr(scope_bindings_json) {
        Some(value) => value,
        None => return std::ptr::null_mut(),
    };
    let scope_prefix = parse_optional_cstr(scope_prefix).unwrap_or_else(|| "scope".to_string());

    let bindings: BTreeSet<String> = match serde_json::from_str(&scope_bindings_json) {
        Ok(vec) => {
            let v: Vec<String> = vec;
            v.into_iter().collect()
        }
        Err(_) => return std::ptr::null_mut(),
    };

    let Some(result) = template_expression::rewrite(&expression, &bindings, &scope_prefix) else {
        return std::ptr::null_mut();
    };
    match CString::new(result) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn transpile_source(source: &str, source_path: &str) -> Option<String> {
    let allocator = Allocator::default();
    let source_type = SourceType::from_path(source_path).unwrap_or(SourceType::ts());
    let parsed = Parser::new(&allocator, source, source_type).parse();
    if !parsed.errors.is_empty() {
        return None;
    }

    let mut program = parsed.program;
    let semantic = SemanticBuilder::new().build(&program);
    let scoping = semantic.semantic.into_scoping();
    let options = TransformOptions::default();
    let _ = Transformer::new(&allocator, Path::new(source_path), &options)
        .build_with_scoping(scoping, &mut program);

    let generated = Codegen::new()
        .with_options(CodegenOptions::default())
        .build(&program);
    Some(generated.code)
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_lower_cells(
    source: *const c_char,
    source_path: *const c_char,
    bindings: *const c_char,
) -> *mut c_char {
    let Some(source) = parse_required_cstr(source) else {
        return std::ptr::null_mut();
    };
    let Some(path) = parse_required_cstr(source_path) else {
        return std::ptr::null_mut();
    };
    let Some(bindings) = parse_required_cstr(bindings) else {
        return std::ptr::null_mut();
    };
    let names: Vec<String> = match serde_json::from_str(&bindings) {
        Ok(names) => names,
        Err(_) => return std::ptr::null_mut(),
    };
    let result = match cells::lower(&source, &path, &names) {
        Ok(code) => serde_json::json!({"code": code, "error": null}),
        Err(error) => serde_json::json!({"code": "", "error": error}),
    };
    CString::new(result.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_cell_script_diagnostics(
    source: *const c_char,
    path: *const c_char,
    bindings: *const c_char,
    module: bool,
) -> *mut c_char {
    let (Some(source), Some(path), Some(bindings)) = (
        parse_required_cstr(source),
        parse_required_cstr(path),
        parse_required_cstr(bindings),
    ) else {
        return std::ptr::null_mut();
    };
    let Ok(names) = serde_json::from_str::<Vec<String>>(&bindings) else {
        return std::ptr::null_mut();
    };
    let result = cell_diagnostics::inspect(&source, &path, &names, module);
    CString::new(serde_json::to_string(&result).unwrap())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_cell_expression_supported(source: *const c_char) -> bool {
    parse_required_cstr(source).is_some_and(|source| cells::validate_expression(&source))
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_cell_handler_supported(source: *const c_char) -> bool {
    parse_required_cstr(source).is_some_and(|source| cells::validate_handler_expression(&source))
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_cell_handler_kind(source: *const c_char) -> u8 {
    parse_required_cstr(source).map_or(0, |source| template_expression::handler_kind(&source))
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_lower_cells_with_expressions(
    source: *const c_char,
    path: *const c_char,
    bindings: *const c_char,
    expressions: *const c_char,
) -> *mut c_char {
    let (Some(source), Some(path), Some(bindings), Some(expressions)) = (
        parse_required_cstr(source),
        parse_required_cstr(path),
        parse_required_cstr(bindings),
        parse_required_cstr(expressions),
    ) else {
        return std::ptr::null_mut();
    };
    let Ok(names) = serde_json::from_str::<Vec<String>>(&bindings) else {
        return std::ptr::null_mut();
    };
    let result = match cells::lower_with_expressions(&source, &path, &names, &expressions) {
        Ok(code) => serde_json::json!({"code":code,"error":null}),
        Err(error) => serde_json::json!({"code":"","error":error}),
    };
    CString::new(result.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_lower_module_cells(
    source: *const c_char,
    path: *const c_char,
    companion: *const c_char,
    bindings: *const c_char,
) -> *mut c_char {
    let (Some(source), Some(path), Some(companion), Some(bindings)) = (
        parse_required_cstr(source),
        parse_required_cstr(path),
        parse_required_cstr(companion),
        parse_required_cstr(bindings),
    ) else {
        return std::ptr::null_mut();
    };
    let Ok(names) = serde_json::from_str::<Vec<String>>(&bindings) else {
        return std::ptr::null_mut();
    };
    let result = match module_cells::lower(&source, &path, &companion, &names) {
        Ok(code) => serde_json::json!({"code": code, "error": null}),
        Err(error) => serde_json::json!({"code": "", "error": error}),
    };
    CString::new(result.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[unsafe(no_mangle)]
pub extern "C" fn weiv_analyze_module_state(
    source: *const c_char,
    path: *const c_char,
) -> *mut c_char {
    let Some(source) = parse_required_cstr(source) else {
        return std::ptr::null_mut();
    };
    let Some(path) = parse_required_cstr(path) else {
        return std::ptr::null_mut();
    };
    serde_json::to_string(&module_state::analyze(&source, &path))
        .ok()
        .and_then(|json| CString::new(json).ok())
        .map_or(std::ptr::null_mut(), CString::into_raw)
}
