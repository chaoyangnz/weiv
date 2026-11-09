import std.io;
import { compile_report, take_unit } from .compiler.compile;
import { ComponentCompileReport } from .compiler.component_unit;
import { Span } from .compiler.source;
import { build as build_browser } from .compiler.backend.browser.build_component;
import { emit as emit_scoped_css } from .compiler.backend.browser.emit.emit_scoped_css;
import { emit_with_selection as emit_browser_module } from .compiler.backend.browser.emit.emit_module;
import { ImportOverride } from .compiler.backend.browser.emit.javascript_module;
import { format as inspect_render_tree } from .compiler.inspect.render_tree;
import { format as inspect_lir } from .compiler.inspect.lir;
import { format as inspect_ast } from .compiler.inspect.ast;
import { format as inspect_sir } from .compiler.inspect.sir;
import { format as inspect_invalidation_graph } from .compiler.inspect.invalidation_graph;
import { parse as parse_sfc, ParseError } from .compiler.parser.sfc.parse;
import { SfcDocument } from .compiler.parser.sfc.ast;
import { parse as parse_template } from .compiler.parser.template.parse;
import { TemplateParseError } from .compiler.parser.template.errors;
import std.process;
import { Stdio } from std.process;
import std.fs;
import { FsError } from std.fs;
import std.mem;
import { lower_module_cells_raw, analyze_module_state_raw, analyze_raw, canonical_path, write_stderr } from .ffi.script_backend;
import { decode as decode_module_cells } from .compiler.backend.browser.emit.js_module.decode_cell_output;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { dirname } from std.path;
import { normalize } from .compiler.project.resolve_component_path;
import { resolve_local } from .compiler.project.module_graph;
import { collect, GraphError } from .compiler.project.collect_component_graph;
import { ComponentGraph, ComponentNode } from .compiler.project.component_graph;
import { ScriptFacts } from .compiler.sema.script_facts;
import { build, component_manifests, ProjectBuildError } from .compiler.project.build_project;
import { write, write_with_runtime } from .compiler.project.write_project;
import { format as inspect_project } from .compiler.project.inspect_project;
import { format as inspect_component, format_unit as inspect_component_unit, format_report as inspect_component_report } from .compiler.inspect.component;
import { write_preview } from .compiler.project.write_preview;
import { write as write_developer } from .compiler.project.write_developer;
import { emit as emit_managed_project } from .compiler.project.managed_project;
import { write as write_project_diagnostics } from .compiler.project.diagnostics;
import { write_failure, write_text_failure, encode_report, encode_text_failure, encode_validation, location } from .compiler.project.diagnostics;
import { ProjectDiagnostic, DiagnosticLocation } from .compiler.project.diagnostics;
import { CompilationStage, SourceOrigin } from .compiler.diagnostics;
import { inspect as inspect_cell_diagnostics, inspect_module as inspect_cell_module_diagnostics, inspect_component as inspect_component_cell_diagnostics } from .compiler.project.cell_diagnostics;
import { analyze as analyze_state_boundaries } from .compiler.project.state_boundaries;
import { empty as empty_selection } from .compiler.backend.browser.emit.cell_selection;
import { select_into as select_local } from .compiler.backend.browser.emit.select_local_state;
import { append as append_javascript, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;

fn write_error_line(message: string): void {
    const line = $"{message}\n";
    write_stderr(line) catch (code) {
        io.write_line(message);
    };
}

fn fs_error_label(code: FsError): string {
    return switch code {
        .not_found => "FileNotFound";
        .permission_denied => "AccessDenied";
        .already_exists => "PathAlreadyExists";
        .invalid_path => "BadPathName";
        .io_error => "InputOutput";
    };
}

fn write_cli_failure(
    action: string,
    path: string,
    code: string,
    stage: string,
    detail: string,
    error_name: string,
    json: bool
): void {
    var diagnostics = list<ProjectDiagnostic>();
    diagnostics.push(ProjectDiagnostic {
        code: code,
        severity: "error",
        stage: stage,
        message: $"{detail} ({error_name})",
        source_path: path,
        span: none,
        location: none,
        fatal: true
    });
    if json {
        write_failure(action, path, &diagnostics) catch (failure) {
            write_error_line("Cannot write diagnostics");
        };
    } else {
        write_text_failure(action, path, &diagnostics) catch (failure) {
            write_error_line("Cannot write diagnostics");
        };
    }
}

fn write_usage(): void {
    const usage = "Usage:\n  weiv --json-diagnostics <command...>\n  weiv analyze script <path>\n  weiv analyze component <path> [--json]\n  weiv validate app <root.weiv> [--json]\n  weiv emit ast <path> [out-file]\n  weiv emit sir <path> [out-file]\n  weiv emit lir <path> [out-file]\n  weiv emit render-tree <path> [out-file]\n  weiv emit invalidation-graph <path> [out-file]\n  weiv emit js <path> [out-file]\n  weiv emit managed-project <manifest.json> <out-dir>  (bundler integration)\n  weiv --runtime-dir <directory> <command>  (packaged runtime location)\n  weiv emit css <path> [out-file]\n  weiv compile <root.weiv> [out-dir]\n  weiv dev <root.weiv> [out-dir]\n\nCompatibility / internal:\n  weiv compile analyze script <path>\n  weiv compile analyze component <path>\n  weiv compile validate app <root.weiv> [--json]\n  weiv compile emit ast <path> [out-file]\n  weiv compile emit sir <path> [out-file]\n  weiv compile emit lir <path> [out-file]\n  weiv compile emit render-tree <path> [out-file]\n  weiv compile emit invalidation-graph <path> [out-file]\n  weiv compile emit js <path> [out-file]\n  weiv compile emit css <path> [out-file]\n  weiv compile emit app <root.weiv> <out-dir>\n  weiv analyze-script <path>\n  weiv analyze-component <path>\n  weiv analyze state-boundaries <path> (dependency diagnostics)\n  weiv analyze module-state <path>     (module provenance facts)\n  weiv emit module-cells <path> <companion-import> <bindings-json>  (internal prototype)\n  weiv emit-js <path> [out-file]\n  weiv emit-css <path> [out-file]\n  weiv emit-app <root.weiv> <out-dir>\n  weiv validate-app <root.weiv> [--json]\n";
    write_stderr(usage) catch (code) {
        io.write_string(usage);
    };
}

fn write_output(path: ?string, data: string): bool {
    if path is output {
        fs.write_file(output, data) catch (code) {
            write_error_line("Cannot write output file");
            return false;
        };
        return true;
    } else {
        io.write_string(data);
        return true;
    }
}

fn sfc_error_name(error: ParseError): string {
    return switch error {
        ParseError.missing_template => "MissingTemplate";
        ParseError.missing_script => "MissingScript";
        ParseError.duplicate_template => "DuplicateTemplate";
        ParseError.duplicate_script => "DuplicateScript";
        ParseError.duplicate_style => "DuplicateStyle";
        ParseError.unknown_top_level_section => "UnknownTopLevelSection";
        ParseError.invalid_script_attributes => "InvalidScriptAttributes";
        ParseError.invalid_section_order => "InvalidSectionOrder";
        ParseError.unterminated_open_tag => "UnterminatedOpenTag";
        ParseError.unterminated_close_tag => "UnterminatedCloseTag";
    };
}

fn template_error_name(error: TemplateParseError): string {
    return switch error {
        TemplateParseError.unexpected_close_tag => "UnexpectedCloseTag";
        TemplateParseError.unterminated_tag => "UnterminatedTag";
        TemplateParseError.unterminated_interpolation => "UnterminatedInterpolation";
        TemplateParseError.mismatched_close_tag => "MismatchedCloseTag";
        TemplateParseError.invalid_directive => "InvalidDirective";
        TemplateParseError.invalid_slot_outlet => "InvalidSlotOutlet";
    };
}

fn write_ast_failure(path: string, error_name: string, json: bool): void {
    var diagnostics = list<ProjectDiagnostic>();
    diagnostics.push(ProjectDiagnostic {
        code: "ast.emit_failed",
        severity: "error",
        stage: "template_parse",
        message: $"emit ast ({error_name})",
        source_path: path,
        span: none,
        location: none,
        fatal: true
    });
    if json {
        write_failure("emit ast", path, &diagnostics) catch (code) {
            write_error_line("Cannot write diagnostics");
        };
    } else {
        write_text_failure("emit ast", path, &diagnostics) catch (code) {
            write_error_line("Cannot write diagnostics");
        };
    }
}

fn emit_ast_document(source: string, path: string, output: ?string, sfc: &const SfcDocument, json: bool): i32 {
    const bytes = source.bytes();
    const template_span = sfc.template.content_span;
    const template_source = string.from(bytes[template_span.start..template_span.end]);
    var document = parse_template(template_source.bytes()) catch (code) {
        write_ast_failure(path, template_error_name(code), json);
        return 1;
    };
    const formatted = inspect_ast(source, &document, sfc, path);
    if not write_output(output, formatted) {
        return 1;
    }
    return 0;
}

fn run_emit_ast(path: string, output: ?string, json: bool): i32 {
    const source = fs.read_file(path) catch (code) {
        write_cli_failure("emit ast", path, "cli.read_failed", "sfc_parse", "emit ast", fs_error_label(code), json);
        return 1;
    };
    var sfc = parse_sfc(source.bytes()) catch (code) {
        write_ast_failure(path, sfc_error_name(code), json);
        return 1;
    };
    return emit_ast_document(source, path, output, &sfc, json);
}

fn run_emit_sir(path: string, output: ?string, report: &const ComponentCompileReport, json: bool): i32 {
    if report.script is script {
        if report.template_bindings is bindings {
            const formatted = inspect_sir(path, &script.facts, &bindings);
            if not write_output(output, formatted) {
                return 1;
            }
            return 0;
        }
    }
    write_compile_failure("emit sir", path, report, json);
    return 1;
}

fn write_compile_failure(action: string, path: string, report: &const ComponentCompileReport, json: bool): void {
    var formatted = inspect_component(report);
    if not json {
        const report_text = inspect_component_report(report);
        formatted = $"weiv {action} failed for {path}\n{report_text}";
    }
    write_stderr(formatted) catch (code) {
        write_error_line(formatted);
    };
}

fn empty_manifests(): ComponentManifests {
    return {
        entries: list<ComponentSlotManifest>()
    };
}

fn compile_direct(path: string, action: string, json: bool): ?ComponentCompileReport {
    const source = fs.read_file(path) catch (code) {
        write_cli_failure(action, path, "cli.read_failed", "sfc_parse", action, fs_error_label(code), json);
        return none;
    };
    const manifests = empty_manifests();
    return compile_report(source, path, &manifests);
}

fn diagnostics_have_fatal(diagnostics: &const List<ProjectDiagnostic>): bool {
    var i: usize = 0;
    while i < diagnostics.len() {
        if diagnostics[i].fatal {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn append_component_diagnostics(
    report: &const ComponentCompileReport,
    source_path: string,
    diagnostics: &List<ProjectDiagnostic>
): void {
    const current = component_failure_diagnostics(report, source_path);
    var i: usize = 0;
    while i < current.len() {
        diagnostics.push(current[i]);
        i = i + 1;
    }
}

fn run_validate_app_direct(path: string, report_json: bool, diagnostics_json: bool): i32 {
    const entry_path = canonical_path(path) catch (code) => path;
    const root = dirname(entry_path);
    var diagnostics = list<ProjectDiagnostic>();
    const graph = collect(root, entry_path) catch (code) {
        const source = fs.read_file(entry_path) catch (read_code) {
            write_cli_failure("validate app", path, "app.validate_failed", "bundle", "validate app", fs_error_label(read_code), diagnostics_json);
            return 1;
        };
        const manifests: ComponentManifests = {
            entries: list<ComponentSlotManifest>()
        };
        const report = compile_report(source, entry_path, &manifests);
        append_component_diagnostics(&report, entry_path, &diagnostics);
        if diagnostics.len() == 0 {
            write_cli_issue("validate app", path, "app.validate_failed", "App validation failed: component graph collection failed.", diagnostics_json);
            return 1;
        }
        if report_json {
            const formatted = encode_validation(path, &diagnostics);
            io.write_string(formatted);
        } else {
            const formatted = encode_text_failure("validate app", path, &diagnostics);
            write_stderr(formatted) catch (error) {
                io.write_string(formatted);
            };
        }
        if diagnostics_have_fatal(&diagnostics) {
            return 1;
        }
        return 0;
    };
    var node_index: usize = 0;
    while node_index < graph.nodes.len() {
        const node = &graph.nodes[node_index];
        const manifests = component_manifests(&graph, node.path) catch (failure) {
            break;
        };
        const report = compile_report(node.source, node.path, &manifests);
        append_component_diagnostics(&report, node.path, &diagnostics);
        node_index = node_index + 1;
    }
    if report_json {
        const formatted = encode_validation(path, &diagnostics);
        io.write_string(formatted);
    } else if diagnostics.len() == 0 {
        io.write_line("app validation ok");
    } else {
        const formatted = encode_text_failure("validate app", path, &diagnostics);
        write_stderr(formatted) catch (error) {
            io.write_string(formatted);
        };
    }
    if diagnostics_have_fatal(&diagnostics) {
        return 1;
    }
    return 0;
}

fn run_analyze_component_direct(path: string, report_json: bool, diagnostics_json: bool): i32 {
    const report = compile_direct(path, "read component", diagnostics_json);
    if report is value {
        if report_json {
            io.write_string(inspect_component(&value));
            return 0;
        }
        var unit_report = value;
        const unit = take_unit(&unit_report) catch (code) {
            io.write_string(inspect_component_report(&unit_report));
            return 0;
        };
        io.write_string(inspect_component_unit(unit, &unit_report));
        return 0;
    }
    return 1;
}

fn run_analyze_boundaries_direct(path: string, json: bool): i32 {
    const report = compile_direct(path, "read component", json);
    if report is value {
        if value.failure is failure {
            write_compile_failure("compile component", path, &value, json);
            return 1;
        }
        var unit_report = value;
        const unit = take_unit(&unit_report) catch (code) {
            write_compile_failure("compile component", path, &unit_report, json);
            return 1;
        };
        const diagnostics = analyze_state_boundaries(&unit, path);
        io.write_string(encode_report(path, &diagnostics));
        return 0;
    }
    return 1;
}

fn run_emit_lir_direct(path: string, output: ?string, json: bool): i32 {
    const report = compile_direct(path, "read component", json);
    if report is value {
        if value.failure is failure {
            write_compile_failure("compile component", path, &value, json);
            return 1;
        }
        if value.sfc_document is sfc {
            if value.lir_document is document {
                const bytes = value.source.bytes();
                const template = string.from(bytes[sfc.template.content_span.start..sfc.template.content_span.end]);
                const formatted = inspect_lir(template, &document);
                if not write_output(output, formatted) {
                    return 1;
                }
                return 0;
            }
        }
        write_compile_failure("compile component", path, &value, json);
        return 1;
    }
    return 1;
}

fn run_emit_render_direct(path: string, output: ?string, json: bool): i32 {
    const report = compile_direct(path, "read component", json);
    if report is value {
        if value.failure is failure {
            write_compile_failure("compile component", path, &value, json);
            return 1;
        }
        var unit_report = value;
        const unit = take_unit(&unit_report) catch (code) {
            write_compile_failure("compile component", path, &unit_report, json);
            return 1;
        };
        const browser = build_browser(unit);
        const bytes = browser.unit.source.bytes();
        const span = browser.unit.sfc_document.template.content_span;
        const template = string.from(bytes[span.start..span.end]);
        const formatted = inspect_render_tree(template, &browser.render_tree);
        if not write_output(output, formatted) {
            return 1;
        }
        return 0;
    }
    return 1;
}

fn run_emit_css_direct(path: string, output: ?string, json: bool): i32 {
    const report = compile_direct(path, "read component", json);
    if report is value {
        if value.failure is failure {
            write_compile_failure("compile component", path, &value, json);
            return 1;
        }
        var unit_report = value;
        const unit = take_unit(&unit_report) catch (code) {
            write_compile_failure("compile component", path, &unit_report, json);
            return 1;
        };
        const css = emit_scoped_css(&unit) catch (code) {
            write_error_line("Cannot emit scoped CSS");
            return 1;
        };
        if not write_output(output, css) {
            return 1;
        }
        return 0;
    }
    return 1;
}

fn run_emit_js_direct(path: string, output: ?string, json: bool): i32 {
    const report = compile_direct(path, "read component", json);
    if report is value {
        if value.failure is failure {
            write_compile_failure("compile component", path, &value, json);
            return 1;
        }
        var unit_report = value;
        const unit = take_unit(&unit_report) catch (code) {
            write_compile_failure("compile component", path, &unit_report, json);
            return 1;
        };
        const boundary_diagnostics = analyze_state_boundaries(&unit, path);
        const browser = build_browser(unit);
        const overrides = list<ImportOverride>();
        var selection = empty_selection();
        select_local(&browser, &selection);
        const diagnostics = inspect_component_cell_diagnostics(&browser, &selection, path);
        if diagnostics.len() > 0 {
            const reported = write_diagnostics("emit js", path, &diagnostics, json);
            if reported {
                return 1;
            }
        }
        if boundary_diagnostics.len() > 0 {
            write_project_diagnostics(&boundary_diagnostics) catch (code) {
                return 1;
            };
        }
        const output_module = emit_browser_module(&browser, &overrides, &selection) catch (code) {
            write_error_line("Cannot emit JavaScript");
            return 1;
        };
        if not write_output(output, output_module.code) {
            return 1;
        }
        return 0;
    }
    return 1;
}

fn build_error_label(code: ProjectBuildError): string {
    return switch code {
        ProjectBuildError.invalid_component => "invalid component";
        ProjectBuildError.missing_import => "missing component import";
        ProjectBuildError.compile_failure => "component compilation failed";
        ProjectBuildError.emit_failure => "browser emission failed";
        ProjectBuildError.module_read_failure => "JavaScript module read failed";
        ProjectBuildError.module_path_invalid => "JavaScript module path is invalid";
        ProjectBuildError.module_collision => "module output path collision";
        ProjectBuildError.module_analysis => "JavaScript module analysis failed";
        ProjectBuildError.module_transpile => "TypeScript module transpilation failed";
        ProjectBuildError.module_lower => "managed module lowering failed";
        ProjectBuildError.managed_selection => "managed state selection failed";
        ProjectBuildError.ambiguous_managed_export => "ambiguous managed export";
    };
}

fn compilation_stage_label(stage: CompilationStage): string {
    return switch stage {
        .sfc_parse => "sfc_parse";
        .template_parse => "template_parse";
        .template_normalize => "template_normalize";
        .script_backend => "script_backend";
        .script_decode => "script_decode";
        .script_facts => "script_facts";
        .binding => "binding";
        .lowering => "lowering";
        .emit => "emit";
    };
}

fn component_failure_diagnostics(report: &const ComponentCompileReport, document_path: string): List<ProjectDiagnostic> {
    var diagnostics = list<ProjectDiagnostic>();
    var i: usize = 0;
    while i < report.diagnostics.len() {
        const diagnostic = &report.diagnostics[i];
        if diagnostic.code == "invalid_script" and report.diagnostics.len() > 1 {
            i = i + 1;
            continue;
        }
        var span: ?Span = diagnostic.span;
        if diagnostic.span is relative {
            var offset = relative.start;
            if report.sfc_document is sfc {
                if diagnostic.origin == SourceOrigin.script {
                    offset = offset + sfc.script.content_span.start;
                } else if diagnostic.origin == SourceOrigin.template {
                    offset = offset + sfc.template.content_span.start;
                }
            }
            span = Span {
                start: offset,
                end: offset + relative.end - relative.start
            };
        }
        var diagnostic_location: ?DiagnosticLocation = none;
        if span is absolute {
            diagnostic_location = location(report.source, absolute.start);
        }
        diagnostics.push(ProjectDiagnostic {
            code: diagnostic.code,
            severity: diagnostic.severity,
            stage: compilation_stage_label(diagnostic.stage),
            message: diagnostic.message,
            source_path: document_path,
            span: span,
            location: diagnostic_location,
            fatal: diagnostic.fatal
        });
        i = i + 1;
    }
    return diagnostics;
}

fn module_cell_error_label(code: JavaScriptError): string {
    return switch code {
        .cell_assignment_pattern_unsupported => "assignment pattern unsupported";
        .cell_var_declaration_unsupported => "var declaration unsupported";
        .cell_dynamic_eval_unsupported => "dynamic eval unsupported";
        .cell_top_level_await_unsupported => "top-level await unsupported";
        .cell_ambient_declaration_unsupported => "ambient declaration unsupported";
        .cell_const_assignment_unsupported => "const assignment unsupported";
        .cell_reserved_identifier => "reserved identifier";
        .cell_template_untracked_assignment_unsupported => "untracked template assignment unsupported";
        .cell_component_default_export_unsupported => "component default export unsupported";
        .cell_declaration_unsupported => "declaration unsupported";
        .invalid_backend_response => "invalid backend response";
        _ => "module lowering failed";
    };
}

fn runtime_complete(path: string): bool {
    const names: [6]string = ["binding.js", "cell.js", "index.js", "observable.js", "reactive-core.js", "router.js"];
    for name in names {
        const found = fs.exists($"{path}/{name}") catch (code) {
            return false;
        };
        if not found {
            return false;
        }
    }
    return true;
}

fn run_dev_driver(output: string, entry: string, runtime: string): i32 {
    write_developer(output) catch (code) {
        write_error_line("Cannot write development driver");
        return 1;
    };
    const binary = process.exe_path() catch (code) {
        write_error_line("Cannot determine executable path");
        return 1;
    };
    const status = process.command("bun")
    .arg("dev.ts")
    .cwd(output)
    .env("WEIV_DEV_ROOT", entry)
    .env("WEIV_DEV_OUT", output)
    .env("WEIV_DEV_BIN", binary)
    .env("WEIV_DEV_RUNTIME", runtime)
    .stdin(Stdio.inherit)
    .stdout(Stdio.inherit)
    .stderr(Stdio.inherit)
    .run() catch (code) {
        write_error_line("Cannot start Bun preview server");
        return 1;
    };
    if status.success {
        return 0;
    }
    return 1;
}

fn encode_names(names: &const List<string>): string {
    var out = list<u8>();
    append_javascript(&out, "[");
    var i: usize = 0;
    while i < names.len() {
        if i > 0 {
            append_javascript(&out, ",");
        }
        emit_string(names[i], &out);
        i = i + 1;
    }
    append_javascript(&out, "]");
    return string.from(out.view());
}

fn script_binding_names(script: &const ScriptFacts): List<string> {
    var names = list<string>();
    var i: usize = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        if binding.template_visible {
            names.push(string.from(binding.name.bytes()));
        }
        i = i + 1;
    }
    return names;
}

fn node_cell_diagnostics(graph: &const ComponentGraph, node: &const ComponentNode, document_path: string): List<ProjectDiagnostic> {
    const manifests = component_manifests(graph, node.path) catch (code) {
        return list<ProjectDiagnostic>();
    };
    var report = compile_report(node.source, node.path, &manifests);
    if report.script is script {
        if report.sfc_document is section {
            const span = section.script.content_span;
            const source = string.from(node.source.bytes()[span.start..span.end]);
            const names = script_binding_names(&script.facts);
            const names_json = encode_names(&names);
            const diagnostics = inspect_cell_diagnostics(source, node.path, document_path, node.source, span.start, names_json, false);
            if diagnostics.len() > 0 {
                return diagnostics;
            }
        }
    }
    const unit = take_unit(&report) catch (code) {
        return list<ProjectDiagnostic>();
    };
    const browser = build_browser(unit);
    var selection = empty_selection();
    select_local(&browser, &selection);
    return inspect_component_cell_diagnostics(&browser, &selection, document_path);
}

fn write_diagnostics(action: string, source_path: string, diagnostics: &const List<ProjectDiagnostic>, json: bool): bool {
    if json {
        write_failure(action, source_path, diagnostics) catch (code) {
            return false;
        };
    } else {
        write_text_failure(action, source_path, diagnostics) catch (code) {
            return false;
        };
    }
    return true;
}

fn write_cli_issue(action: string, source_path: string, code: string, message: string, json: bool): void {
    var diagnostics = list<ProjectDiagnostic>();
    diagnostics.push(ProjectDiagnostic {
        code: code,
        severity: "error",
        stage: "bundle",
        message: message,
        source_path: source_path,
        span: none,
        location: none,
        fatal: true
    });
    if json {
        write_failure(action, source_path, &diagnostics) catch (error) {
            io.write_line("Cannot write diagnostics");
        };
    } else {
        write_text_failure(action, source_path, &diagnostics) catch (error) {
            io.write_line("Cannot write diagnostics");
        };
    }
}

fn is_retired_reactivity_name(name: string): bool {
    const bytes = name.bytes();
    return mem.ends_with(bytes, "-legacy".bytes()) or name == "js-cells" or name == "app-cells";
}

fn write_retired_reactivity_issue(name: string, json: bool): void {
    var diagnostics = list<ProjectDiagnostic>();
    diagnostics.push(ProjectDiagnostic {
        code: "cli.reactivity_mode_removed",
        severity: "error",
        stage: "emit",
        message: "This reactivity mode has been removed. Use emit js or emit app, remove weivUpdate wrappers, and wait for the queued DOM batch before reading updated DOM.",
        source_path: name,
        span: none,
        location: none,
        fatal: true
    });
    if json {
        write_failure("emit", name, &diagnostics) catch (error) {
            io.write_line("Cannot write diagnostics");
        };
    } else {
        write_text_failure("emit", name, &diagnostics) catch (error) {
            io.write_line("Cannot write diagnostics");
        };
    }
}

fn write_emit_js_diagnostics(graph: &const ComponentGraph, document_path: string, json: bool): bool {
    if graph.find_node(graph.entry_path) is index {
        const diagnostics = node_cell_diagnostics(graph, &graph.nodes[index], document_path);
        if diagnostics.len() > 0 {
            return write_diagnostics("emit js", document_path, &diagnostics, json);
        }
    }
    return false;
}

fn write_state_boundary_warnings(graph: &const ComponentGraph, document_path: string): void {
    if graph.find_node(graph.entry_path) is index {
        const node = &graph.nodes[index];
        const manifests = component_manifests(graph, node.path) catch (code) {
            return;
        };
        var report = compile_report(node.source, node.path, &manifests);
        const unit = take_unit(&report) catch (code) {
            return;
        };
        const diagnostics = analyze_state_boundaries(&unit, document_path);
        if diagnostics.len() > 0 {
            write_project_diagnostics(&diagnostics) catch (code) {
                return;
            };
        }
    }
}

fn write_app_cell_diagnostics(graph: &const ComponentGraph, json: bool): bool {
    var i: usize = 0;
    while i < graph.nodes.len() {
        const node = &graph.nodes[i];
        const diagnostics = node_cell_diagnostics(graph, node, node.path);
        if diagnostics.len() > 0 {
            return write_diagnostics("emit app", graph.entry_path, &diagnostics, json);
        }
        i = i + 1;
    }
    return false;
}

fn write_app_module_diagnostics(graph: &const ComponentGraph, json: bool, include_cells: bool): bool {
    var visited = list<string>();
    var node_index: usize = 0;
    while node_index < graph.nodes.len() {
        const node = &graph.nodes[node_index];
        const manifests = component_manifests(graph, node.path) catch (code) {
            return false;
        };
        const report = compile_report(node.source, node.path, &manifests);
        if report.script is script {
            var import_index: usize = 0;
            while import_index < script.facts.imports.len() {
                const record = &script.facts.imports[import_index];
                if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                    if not mem.ends_with(record.source.bytes(), ".weiv".bytes()) {
                        const path = resolve_local(node.path, record.source) catch (code) {
                            import_index = import_index + 1;
                            continue;
                        };
                        var seen = false;
                        var j: usize = 0;
                        while j < visited.len() {
                            if visited[j] == path {
                                seen = true;
                            }
                            j = j + 1;
                        }
                        if not seen {
                            visited.push(string.from(path.bytes()));
                            const source = fs.read_file(path) catch (code) {
                                import_index = import_index + 1;
                                continue;
                            };
                            var names = list<string>();
                            var k: usize = 0;
                            while k < graph.nodes.len() {
                                const candidate = &graph.nodes[k];
                                const candidate_manifests = component_manifests(graph, candidate.path) catch (code) {
                                    k = k + 1;
                                    continue;
                                };
                                const candidate_report = compile_report(candidate.source, candidate.path, &candidate_manifests);
                                if candidate_report.script is candidate_script {
                                    var candidate_import: usize = 0;
                                    while candidate_import < candidate_script.facts.imports.len() {
                                        const imported_record = &candidate_script.facts.imports[candidate_import];
                                        if (mem.starts_with(imported_record.source.bytes(), "./".bytes()) or mem.starts_with(imported_record.source.bytes(), "../".bytes())) and not mem.ends_with(imported_record.source.bytes(), ".weiv".bytes()) {
                                            const imported_path = resolve_local(candidate.path, imported_record.source) catch (code) {
                                                candidate_import = candidate_import + 1;
                                                continue;
                                            };
                                            if imported_path == path {
                                                var name = imported_record.local_name;
                                                if imported_record.imported_name is imported_name {
                                                    name = imported_name;
                                                }
                                                var duplicate = false;
                                                var n: usize = 0;
                                                while n < names.len() {
                                                    if names[n] == name {
                                                        duplicate = true;
                                                    }
                                                    n = n + 1;
                                                }
                                                if not duplicate {
                                                    names.push(string.from(name.bytes()));
                                                }
                                            }
                                        }
                                        candidate_import = candidate_import + 1;
                                    }
                                }
                                k = k + 1;
                            }
                            const names_json = encode_names(&names);
                            const diagnostics = inspect_cell_module_diagnostics(source, path, path, source, names_json, include_cells);
                            if diagnostics.len() > 0 {
                                return write_diagnostics("emit app", graph.entry_path, &diagnostics, json);
                            }
                        }
                    }
                }
                import_index = import_index + 1;
            }
        }
        node_index = node_index + 1;
    }
    return false;
}

fn main(): i32 {
    const raw_args = process.args();
    var args = list<string>();
    args.push(raw_args[0]);
    var runtime_dir: ?string = none;
    var json_diagnostics = false;
    var arg_index: usize = 1;
    while arg_index < raw_args.len() {
        const current = string.from(raw_args[arg_index].bytes());
        if current == "--runtime-dir" {
            if arg_index + 1 >= raw_args.len() {
                if json_diagnostics {
                    write_stderr("{\n  \"action\": \"run\",\n  \"sourcePath\": \"<process>\",\n  \"ok\": false,\n  \"diagnostics\": [\n    {\n      \"code\": \"cli.unhandled_error\",\n      \"severity\": \"error\",\n      \"stage\": \"bundle\",\n      \"message\": \"run (MissingRuntimeDirectory)\",\n      \"sourcePath\": \"<process>\",\n      \"span\": null,\n      \"location\": null,\n      \"fatal\": true\n    }\n  ]\n}\n") catch (code) {
                        write_error_line("Cannot write diagnostics");
                        return 1;
                    };
                } else {
                    write_error_line("weiv run failed for <process>\n  error cli.unhandled_error [bundle] fatal: run (MissingRuntimeDirectory)");
                }
                return 1;
            }
            runtime_dir = raw_args[arg_index + 1];
            arg_index = arg_index + 2;
        } else if current == "--json-diagnostics" {
            json_diagnostics = true;
            arg_index = arg_index + 1;
        } else {
            break;
        }
    }
    while arg_index < raw_args.len() {
        args.push(raw_args[arg_index]);
        arg_index = arg_index + 1;
    }

    if args.len() == 1 {
        write_usage();
        return 0;
    }
    if is_retired_reactivity_name(args[1]) {
        write_retired_reactivity_issue(args[1], json_diagnostics);
        return 1;
    }
    if args.len() > 2 and (args[1] == "emit" or args[1] == "analyze" or args[1] == "validate") and is_retired_reactivity_name(args[2]) {
        write_retired_reactivity_issue(args[2], json_diagnostics);
        return 1;
    }
    if args.len() > 3 and args[1] == "compile" and is_retired_reactivity_name(args[3]) {
        write_retired_reactivity_issue(args[3], json_diagnostics);
        return 1;
    }
    if args[1] == "inspect-project" or args[1] == "build-browser" {
        write_usage();
        return 0;
    }

    if args.len() == 2 and (args[1] == "--help" or args[1] == "-h") {
        write_usage();
        return 0;
    }
    const inspect_lir_nested_mode = args.len() >= 4 and args[1] == "inspect" and (args[2] == "lir" or args[2] == "ir");
    const inspect_lir_alias_mode = args.len() >= 3 and (args[1] == "inspect-lir" or args[1] == "dump-lir" or args[1] == "inspect-ir" or args[1] == "dump-ir");
    const emit_lir_compat_mode = args.len() >= 4 and args[1] == "emit" and args[2] == "lir";
    const emit_lir_compile_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and args[3] == "lir";
    const emit_lir_mode = emit_lir_compat_mode or emit_lir_compile_mode;
    const lir_mode = inspect_lir_nested_mode or inspect_lir_alias_mode or emit_lir_mode;
    const inspect_render_nested_mode = args.len() >= 4 and args[1] == "inspect" and (args[2] == "render-tree" or args[2] == "browser-plan");
    const inspect_render_alias_mode = args.len() >= 3 and (args[1] == "inspect-render-tree" or args[1] == "dump-render-tree" or args[1] == "inspect-browser-plan" or args[1] == "dump-browser-plan");
    const emit_render_compat_mode = args.len() >= 4 and args[1] == "emit" and (args[2] == "render-tree" or args[2] == "browser-plan");
    const emit_render_compile_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and (args[3] == "render-tree" or args[3] == "browser-plan");
    const emit_render_mode = emit_render_compat_mode or emit_render_compile_mode;
    const render_mode = inspect_render_nested_mode or inspect_render_alias_mode or emit_render_mode;
    var inspect_invalidation_mode = false;
    if args.len() >= 4 {
        inspect_invalidation_mode = args[1] == "inspect" and args[2] == "invalidation-graph";
    } else if args.len() >= 3 {
        inspect_invalidation_mode = args[1] == "inspect-invalidation-graph" or args[1] == "dump-invalidation-graph";
    }
    var emit_invalidation_mode = false;
    if args.len() >= 4 and args[1] == "emit" {
        emit_invalidation_mode = args[2] == "invalidation-graph";
    } else if args.len() >= 5 and args[1] == "compile" and args[2] == "emit" {
        emit_invalidation_mode = args[3] == "invalidation-graph";
    }
    const invalidation_mode = inspect_invalidation_mode or emit_invalidation_mode;
    const inspect_mode = args.len() >= 3 and args[1] == "inspect-project";
    const emit_ast_compat_mode = args.len() >= 4 and args[1] == "emit" and args[2] == "ast";
    const emit_ast_compile_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and args[3] == "ast";
    const emit_ast_mode = emit_ast_compat_mode or emit_ast_compile_mode;
    const emit_sir_compat_mode = args.len() >= 4 and args[1] == "emit" and args[2] == "sir";
    const emit_sir_compile_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and args[3] == "sir";
    const emit_sir_mode = emit_sir_compat_mode or emit_sir_compile_mode;
    const emit_js_compat_mode = args.len() >= 4 and args[1] == "emit" and args[2] == "js";
    const emit_css_compat_mode = args.len() >= 4 and args[1] == "emit" and args[2] == "css";
    const compile_emit_js_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and args[3] == "js";
    const compile_emit_css_mode = args.len() >= 5 and args[1] == "compile" and args[2] == "emit" and args[3] == "css";
    const emit_js_mode = (args.len() >= 3 and args[1] == "emit-js") or emit_js_compat_mode or compile_emit_js_mode;
    const emit_css_mode = (args.len() >= 3 and args[1] == "emit-css") or emit_css_compat_mode or compile_emit_css_mode;
    const emit_cells_mode = args.len() >= 5 and args[1] == "emit-module-cells";
    const emit_cells_compat_mode = args.len() >= 6 and args[1] == "emit" and args[2] == "module-cells";
    const analyze_module_mode = args.len() >= 4 and args[1] == "analyze" and args[2] == "module-state";
    const analyze_script_mode = (args.len() >= 4 and args[1] == "analyze" and args[2] == "script") or
    (args.len() >= 5 and args[1] == "compile" and args[2] == "analyze" and args[3] == "script") or
    (args.len() >= 3 and args[1] == "analyze-script");
    var analyze_script_path_index: usize = 3;
    if args.len() >= 5 and args[1] == "compile" and args[2] == "analyze" and args[3] == "script" {
        analyze_script_path_index = 4;
    } else if args.len() >= 3 and args[1] == "analyze-script" {
        analyze_script_path_index = 2;
    }
    const analyze_boundaries_mode = args.len() >= 4 and args[1] == "analyze" and args[2] == "state-boundaries";
    const analyze_component_mode = (args.len() >= 4 and args[1] == "analyze" and args[2] == "component") or
    (args.len() >= 3 and args[1] == "analyze-component") or
    (args.len() >= 5 and args[1] == "compile" and args[2] == "analyze" and args[3] == "component");
    var analyze_component_path_index: usize = 3;
    if args.len() >= 5 and args[1] == "compile" and args[2] == "analyze" and args[3] == "component" {
        analyze_component_path_index = 4;
    } else if args.len() >= 3 and args[1] == "analyze-component" {
        analyze_component_path_index = 2;
    }
    const analyze_component_json = args.len() > analyze_component_path_index + 1 and args[analyze_component_path_index + 1] == "--json";
    const validate_app_mode = (args.len() >= 4 and args[1] == "validate" and args[2] == "app") or
    (args.len() >= 3 and args[1] == "validate-app") or
    (args.len() >= 5 and args[1] == "compile" and args[2] == "validate" and args[3] == "app");
    var validate_app_path_index: usize = 3;
    if args.len() >= 5 and args[1] == "compile" and args[2] == "validate" and args[3] == "app" {
        validate_app_path_index = 4;
    } else if args.len() >= 3 and args[1] == "validate-app" {
        validate_app_path_index = 2;
    }
    const validate_app_json = args.len() > validate_app_path_index + 1 and args[validate_app_path_index + 1] == "--json";
    const build_mode = (args.len() == 4 or args.len() == 5) and args[1] == "build-browser";
    const preview_compile_mode = args.len() >= 6 and args[1] == "compile" and args[2] == "emit" and args[3] == "app";
    const preview_emit_mode = args.len() >= 5 and args[1] == "emit" and args[2] == "app";
    const emit_app_alias_mode = args.len() >= 4 and args[1] == "emit-app";
    const dev_mode = args.len() >= 3 and args[1] == "dev";
    const compile_is_subcommand = args.len() > 2 and (args[2] == "analyze" or args[2] == "validate" or args[2] == "emit");
    const compile_alias_mode = args.len() >= 3 and args[1] == "compile" and not compile_is_subcommand;
    const preview_mode = preview_compile_mode or preview_emit_mode or emit_app_alias_mode or compile_alias_mode or dev_mode;
    const managed_project_mode = args.len() >= 5 and args[1] == "emit" and args[2] == "managed-project";
    if not lir_mode and not render_mode and not invalidation_mode and not inspect_mode and not emit_ast_mode and not emit_sir_mode and not emit_js_mode and not emit_css_mode and not emit_cells_mode and not emit_cells_compat_mode and not analyze_module_mode and not analyze_script_mode and not analyze_boundaries_mode and not analyze_component_mode and not validate_app_mode and not build_mode and not preview_mode and not managed_project_mode {
        write_usage();
        return 0;
    }
    if emit_cells_mode or emit_cells_compat_mode {
        var path_index: usize = 2;
        if emit_cells_compat_mode {
            path_index = 3;
        }
        const source = fs.read_file(args[path_index]) catch (code) {
            io.write_line("Cannot read JavaScript module");
            return 1;
        };
        const response = lower_module_cells_raw(source, args[path_index], args[path_index + 1], args[path_index + 2]) catch (code) {
            io.write_line("Cannot lower JavaScript module cells");
            return 1;
        };
        const code = decode_module_cells(response) catch (failure) {
            const diagnostics = inspect_cell_diagnostics(source, args[path_index], args[path_index], source, 0, args[path_index + 2], true);
            if diagnostics.len() > 0 {
                if json_diagnostics {
                    write_failure("emit module-cells", args[path_index], &diagnostics) catch (code) {
                        io.write_line("Cannot write diagnostics");
                        return 1;
                    };
                } else {
                    write_text_failure("emit module-cells", args[path_index], &diagnostics) catch (code) {
                        io.write_line("Cannot write diagnostics");
                        return 1;
                    };
                }
                return 1;
            }
            const reason = module_cell_error_label(failure);
            io.write_line($"Cannot lower JavaScript module cells: {reason}");
            return 1;
        };
        io.write_string(code);
        return 0;
    }
    if emit_ast_mode or emit_sir_mode {
        var path_index: usize = 3;
        if emit_ast_compile_mode or emit_sir_compile_mode {
            path_index = 4;
        }
        var output: ?string = none;
        if args.len() > path_index + 1 {
            output = args[path_index + 1];
        }
        if emit_ast_mode {
            return run_emit_ast(args[path_index], output, json_diagnostics);
        }
        const source = fs.read_file(args[path_index]) catch (code) {
            write_cli_failure("emit sir", args[path_index], "cli.read_failed", "sfc_parse", "emit sir", fs_error_label(code), json_diagnostics);
            return 1;
        };
        const manifests: ComponentManifests = {
            entries: list<ComponentSlotManifest>()
        };
        var report = compile_report(source, args[path_index], &manifests);
        return run_emit_sir(args[path_index], output, &report, json_diagnostics);
    }
    if analyze_script_mode {
        const source = fs.read_file(args[analyze_script_path_index]) catch (code) {
            write_cli_failure("analyze script", args[analyze_script_path_index], "cli.read_failed", "script_facts", "analyze script", fs_error_label(code), json_diagnostics);
            return 1;
        };
        const response = analyze_raw(source, args[analyze_script_path_index]) catch (code) {
            io.write_line("Cannot analyze JavaScript script");
            return 1;
        };
        io.write_line(response);
        return 0;
    }
    if analyze_module_mode {
        const source = fs.read_file(args[3]) catch (code) {
            write_cli_failure("analyze module-state", args[3], "cli.read_failed", "script_facts", "analyze module-state", fs_error_label(code), json_diagnostics);
            return 1;
        };
        const response = analyze_module_state_raw(source, args[3]) catch (code) {
            io.write_line("Cannot analyze JavaScript module state");
            return 1;
        };
        io.write_line(response);
        return 0;
    }
    if validate_app_mode {
        return run_validate_app_direct(args[validate_app_path_index], validate_app_json, json_diagnostics);
    }
    if managed_project_mode {
        const cwd_for_manifest = process.cwd() catch (code) {
            io.write_line("Cannot determine current directory");
            return 1;
        };
        var runtime_for_manifest = "packages/weiv/dist/runtime";
        if runtime_dir is path {
            runtime_for_manifest = path;
        }
        if runtime_for_manifest.bytes()[0] != 47 {
            runtime_for_manifest = $"{cwd_for_manifest}/{runtime_for_manifest}";
        }
        if not runtime_complete(runtime_for_manifest) {
            write_cli_issue("emit managed-project", args[3], "cli.runtime_missing", "Cannot write managed project: runtime directory is missing required files.", json_diagnostics);
            return 1;
        }
        var output_for_manifest = args[4];
        if output_for_manifest.bytes().len() == 0 {
            io.write_line("Invalid output path");
            return 1;
        }
        if output_for_manifest.bytes()[0] != 47 {
            output_for_manifest = $"{cwd_for_manifest}/{output_for_manifest}";
        }
        emit_managed_project(args[3], output_for_manifest, runtime_for_manifest) catch (code) {
            io.write_line("Cannot write managed project");
            return 1;
        };
        return 0;
    }
    const cwd = process.cwd() catch (code) {
        write_error_line("Cannot determine current directory");
        return 1;
    };
    var entry_index: usize = 2;
    if emit_js_compat_mode or emit_css_compat_mode or preview_emit_mode {
        entry_index = 3;
    }
    if preview_compile_mode or compile_emit_js_mode or compile_emit_css_mode {
        entry_index = 4;
    }
    if inspect_invalidation_mode and (args[1] == "inspect-invalidation-graph" or args[1] == "dump-invalidation-graph") {
        entry_index = 2;
    } else if inspect_invalidation_mode or (emit_invalidation_mode and args[1] == "emit") {
        entry_index = 3;
    } else if emit_invalidation_mode and args[1] == "compile" {
        entry_index = 4;
    }
    if analyze_component_mode {
        entry_index = analyze_component_path_index;
    } else if analyze_boundaries_mode {
        entry_index = 3;
    } else if validate_app_mode {
        entry_index = validate_app_path_index;
    }
    if inspect_lir_nested_mode or inspect_render_nested_mode or emit_lir_compat_mode or emit_render_compat_mode or emit_css_compat_mode {
        entry_index = 3;
    } else if inspect_lir_alias_mode or inspect_render_alias_mode or (args[1] == "emit-css") {
        entry_index = 2;
    } else if emit_lir_compile_mode or emit_render_compile_mode or compile_emit_css_mode {
        entry_index = 4;
    }
    const entry_arg = args[entry_index];
    var entry_path = entry_arg;
    if entry_arg.bytes().len() == 0 {
        io.write_line("Invalid entry path");
        return 1;
    }
    if entry_arg.bytes()[0] != 47 {
        entry_path = $"{cwd}/{entry_arg}";
    }
    const entry = normalize(entry_path) catch (code) {
        io.write_line("Invalid entry path");
        return 1;
    };
    if analyze_component_mode {
        return run_analyze_component_direct(entry_arg, analyze_component_json, json_diagnostics);
    }
    if analyze_boundaries_mode {
        return run_analyze_boundaries_direct(entry_arg, json_diagnostics);
    }
    if validate_app_mode {
        return run_validate_app_direct(entry_arg, validate_app_json, json_diagnostics);
    }
    if lir_mode or render_mode or emit_css_mode or emit_js_mode {
        var output: ?string = none;
        const emits_output = emit_lir_mode or emit_render_mode or emit_css_mode or emit_js_mode;
        if emits_output and args.len() > entry_index + 1 {
            output = args[entry_index + 1];
        }
        if lir_mode {
            return run_emit_lir_direct(entry_arg, output, json_diagnostics);
        }
        if render_mode {
            return run_emit_render_direct(entry_arg, output, json_diagnostics);
        }
        if emit_css_mode {
            return run_emit_css_direct(entry_arg, output, json_diagnostics);
        }
        return run_emit_js_direct(entry_arg, output, json_diagnostics);
    }
    if invalidation_mode {
        const report = compile_direct(entry_arg, "read component", json_diagnostics);
        if report is value {
            if value.failure is failure {
                write_compile_failure("compile component", entry_arg, &value, json_diagnostics);
                return 1;
            }
            var unit_report = value;
            const unit = take_unit(&unit_report) catch (code) {
                write_compile_failure("compile component", entry_arg, &unit_report, json_diagnostics);
                return 1;
            };
            var browser = build_browser(unit);
            const formatted = inspect_invalidation_graph(&browser);
            if emit_invalidation_mode and args.len() > entry_index + 1 {
                if not write_output(args[entry_index + 1], formatted) {
                    return 1;
                }
            } else {
                io.write_string(formatted);
            }
            return 0;
        }
        return 1;
    }
    const root = dirname(entry);
    const graph = collect(root, entry) catch (code) {
        if code == GraphError.script_analysis or code == GraphError.invalid_component {
            const source = fs.read_file(entry) catch (read_code) {
                io.write_line("Cannot collect component graph");
                return 1;
            };
            const manifests: ComponentManifests = {
                entries: list<ComponentSlotManifest>()
            };
            var report = compile_report(source, entry, &manifests);
            report.source_path = entry_arg;
            const diagnostics = component_failure_diagnostics(&report, entry_arg);
            if diagnostics.len() > 0 {
                var action = "emit js";
                if preview_mode {
                    action = "validate app";
                }
                if write_diagnostics(action, entry_arg, &diagnostics, json_diagnostics) {
                    return 1;
                }
            }
        }
        io.write_line("Cannot collect component graph");
        return 1;
    };
    if analyze_component_mode {
        if graph.find_node(graph.entry_path) is index {
            const node = &graph.nodes[index];
            const manifests = component_manifests(&graph, graph.entry_path) catch (code) {
                io.write_line("Cannot analyze component");
                return 1;
            };
            var report = compile_report(node.source, node.path, &manifests);
            report.source_path = entry_arg;
            if analyze_component_json {
                io.write_string(inspect_component(&report));
            } else {
                const unit = take_unit(&report) catch (code) {
                    io.write_string(inspect_component_report(&report));
                    return 0;
                };
                io.write_string(inspect_component_unit(unit, &report));
            }
            return 0;
        }
        io.write_line("Cannot analyze component");
        return 1;
    }
    if analyze_boundaries_mode {
        if graph.find_node(graph.entry_path) is index {
            const node = &graph.nodes[index];
            const manifests = component_manifests(&graph, graph.entry_path) catch (code) {
                io.write_line("Cannot analyze state boundaries");
                return 1;
            };
            var report = compile_report(node.source, node.path, &manifests);
            const unit = take_unit(&report) catch (code) {
                io.write_line("Cannot analyze state boundaries");
                return 1;
            };
            const diagnostics = analyze_state_boundaries(&unit, entry_arg);
            io.write_string(encode_report(entry_arg, &diagnostics));
            return 0;
        }
        io.write_line("Cannot analyze state boundaries");
        return 1;
    }
    if lir_mode or render_mode or emit_css_mode {
        if graph.find_node(graph.entry_path) is index {
            const node = &graph.nodes[index];
            const manifests = component_manifests(&graph, graph.entry_path) catch (code) {
                io.write_line("Cannot inspect component: component manifests failed");
                return 1;
            };
            var report = compile_report(node.source, node.path, &manifests);
            if report.sfc_document is sfc {
                const bytes = node.source.bytes();
                const template = string.from(bytes[sfc.template.content_span.start..sfc.template.content_span.end]);
                if emit_css_mode {
                    const unit = take_unit(&report) catch (code) {
                        io.write_line("Cannot emit scoped CSS: component compilation failed");
                        return 1;
                    };
                    const css = emit_scoped_css(&unit) catch (code) {
                        io.write_line("Cannot emit scoped CSS");
                        return 1;
                    };
                    var output: ?string = none;
                    if args.len() > entry_index + 1 {
                        output = args[entry_index + 1];
                    }
                    if not write_output(output, css) {
                        return 1;
                    }
                    return 0;
                } else if lir_mode {
                    if report.lir_document is document {
                        const formatted = inspect_lir(template, &document);
                        var output: ?string = none;
                        if emit_lir_mode and args.len() > entry_index + 1 {
                            output = args[entry_index + 1];
                        }
                        if not write_output(output, formatted) {
                            return 1;
                        }
                        return 0;
                    }
                } else {
                    const unit = take_unit(&report) catch (code) {
                        io.write_line("Cannot inspect render tree: component compilation failed");
                        return 1;
                    };
                    const browser = build_browser(unit);
                    const formatted = inspect_render_tree(template, &browser.render_tree);
                    var output: ?string = none;
                    if emit_render_mode and args.len() > entry_index + 1 {
                        output = args[entry_index + 1];
                    }
                    if not write_output(output, formatted) {
                        return 1;
                    }
                    return 0;
                }
            }
        }
        io.write_line("Cannot inspect component: compilation failed");
        return 1;
    }
    if preview_mode {
        if write_app_cell_diagnostics(&graph, json_diagnostics) {
            return 1;
        }
        if write_app_module_diagnostics(&graph, json_diagnostics, false) {
            return 1;
        }
    }
    if preview_mode and not json_diagnostics {
        write_state_boundary_warnings(&graph, entry_arg);
    }
    const project = build(&graph) catch (code) {
        if code == ProjectBuildError.compile_failure or code == ProjectBuildError.emit_failure {
            if emit_js_mode and write_emit_js_diagnostics(&graph, entry_arg, json_diagnostics) {
                return 1;
            }
            if preview_mode and write_app_cell_diagnostics(&graph, json_diagnostics) {
                return 1;
            }
        }
        if preview_mode and (code == ProjectBuildError.module_lower or code == ProjectBuildError.module_analysis) and write_app_module_diagnostics(&graph, json_diagnostics, true) {
            return 1;
        }
        const reason = build_error_label(code);
        io.write_line($"Cannot build browser project: {reason}");
        return 1;
    };
    if emit_js_mode {
        write_state_boundary_warnings(&graph, entry_arg);
    }
    if inspect_mode {
        io.write_line(inspect_project(&graph, &project));
        return 0;
    }
    if emit_js_mode {
        var output: ?string = none;
        if args.len() > entry_index + 1 {
            output = args[entry_index + 1];
        }
        for artifact in &project.modules {
            if artifact.module_path == project.entry_module {
                if write_output(output, artifact.code) {
                    return 0;
                }
                return 1;
            }
        }
        write_error_line("Cannot emit JavaScript: entry module missing");
        return 1;
    }
    if emit_css_mode {
        var output: ?string = none;
        if args.len() > entry_index + 1 {
            output = args[entry_index + 1];
        }
        if write_output(output, project.stylesheet) {
            return 0;
        }
        return 1;
    }
    if preview_mode {
        var runtime = "packages/weiv/dist/runtime";
        if runtime_dir is path {
            runtime = path;
        }
        if runtime.bytes()[0] != 47 {
            runtime = $"{cwd}/{runtime}";
        }
        var preview_output = "dist";
        if preview_emit_mode {
            preview_output = args[4];
        } else if emit_app_alias_mode {
            preview_output = args[3];
        } else if compile_alias_mode and args.len() > 3 {
            preview_output = args[3];
        } else if preview_compile_mode {
            preview_output = args[5];
        } else if dev_mode and args.len() > 3 {
            preview_output = args[3];
        }
        const dev_output_arg = preview_output;
        if preview_output.bytes().len() == 0 {
            io.write_line("Invalid output path");
            return 1;
        }
        if preview_output.bytes()[0] != 47 {
            preview_output = $"{cwd}/{preview_output}";
        }
        if not runtime_complete(runtime) {
            write_cli_issue("emit app", entry_arg, "cli.runtime_missing", "Cannot write preview app: runtime directory is missing required files.", json_diagnostics);
            return 1;
        }
        write_preview(&graph, &project, preview_output, runtime) catch (code) {
            io.write_line("Cannot write preview app");
            return 1;
        };
        if dev_mode {
            const watch_entry = canonical_path(entry) catch (failure) => entry;
            const session = $"weiv dev info session.start: root={entry_arg} out={dev_output_arg}\nweiv dev info watch.starting: starting watch/rebuild loop\n";
            write_stderr(session) catch (failure) {
                io.write_string(session);
            };
            return run_dev_driver(preview_output, watch_entry, runtime);
        }
        if json_diagnostics {
            write_project_diagnostics(&project.diagnostics) catch (code) {
                io.write_line("Cannot write diagnostics");
                return 1;
            };
        }
        return 0;
    }
    const output_arg = args[3];
    var output_path = output_arg;
    if output_arg.bytes().len() == 0 {
        io.write_line("Invalid output path");
        return 1;
    }
    if output_arg.bytes()[0] != 47 {
        output_path = $"{cwd}/{output_arg}";
    }
    const output = normalize(output_path) catch (code) {
        io.write_line("Invalid output path");
        return 1;
    };
    if args.len() == 5 {
        const runtime_arg = args[4];
        var runtime_path = runtime_arg;
        if runtime_arg.bytes().len() == 0 {
            io.write_line("Invalid runtime directory");
            return 1;
        }
        if runtime_arg.bytes()[0] != 47 {
            runtime_path = $"{cwd}/{runtime_arg}";
        }
        const runtime = normalize(runtime_path) catch (code) {
            io.write_line("Invalid runtime directory");
            return 1;
        };
        if not runtime_complete(runtime) {
            write_cli_issue("build-browser", entry_arg, "cli.runtime_missing", "Cannot write browser project: runtime directory is missing required files.", json_diagnostics);
            return 1;
        }
        write_with_runtime(&project, output, runtime) catch (code) {
            io.write_line("Cannot write browser project with runtime");
            return 1;
        };
    } else {
        write(&project, output) catch (code) {
            io.write_line("Cannot write browser project");
            return 1;
        };
    }
    io.write_line($"Built {project.entry_module}");
    return 0;
}
