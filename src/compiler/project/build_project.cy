// Operation: loaded component graph -> imported slot manifests and browser modules.
import { ComponentGraph } from .compiler.project.component_graph;
import { ProjectBuild, ProjectModule } from .compiler.project.project_build;
import { ComponentManifests, ComponentSlotManifest } from .compiler.sema.component_manifests;
import { ComponentUnit } from .compiler.component_unit;
import { SlotManifest, SlotEntry } from .compiler.sema.slot_manifest;
import { parse as parse_sfc } from .compiler.parser.sfc.parse;
import { parse as parse_template } from .compiler.parser.template.parse;
import { normalize } from .compiler.parser.template.normalize;
import { build as build_slot_manifest } from .compiler.sema.build_slot_manifest;
import { compile_report, take_unit } from .compiler.compile;
import { build as build_browser } from .compiler.backend.browser.build_component;
import { emit_with_selection } from .compiler.backend.browser.emit.emit_module;
import { empty as empty_selection } from .compiler.backend.browser.emit.cell_selection;
import { select_into as select_local } from .compiler.backend.browser.emit.select_local_state;
import { select_into as select_managed, ManagedTarget } from .compiler.project.select_managed_state;
import { ModuleEntry, register, resolve_local, is_script_module, mapped, rewrite as rewrite_module_imports } from .compiler.project.module_graph;
import { ImportOverride } from .compiler.backend.browser.emit.javascript_module;
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { decode as decode_cells } from .compiler.backend.browser.emit.js_module.decode_cell_output;
import { ScriptFacts } from .compiler.sema.script_facts;
import { should_preserve } from .compiler.backend.browser.emit.js_module.emit_module_imports;
import { basename } from std.path;
import std.fs;
import std.mem;
import std.json;
import { analyze_module_state_raw, transpile_module_raw, lower_module_cells_raw } from .ffi.script_backend;
import .compiler.sema.script_json as validation;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import { Span } from .compiler.source;
import { ProjectDiagnostic, location } from .compiler.project.diagnostics;

pub enum ProjectBuildError {
    invalid_component;
    missing_import;
    compile_failure;
    emit_failure;
    module_read_failure;
    module_path_invalid;
    module_collision;
    module_analysis;
    module_transpile;
    module_lower;
    managed_selection;
    ambiguous_managed_export;
}

fn replace_module_code(modules: &List<ProjectModule>, index: usize, code: string): void {
    const artifact = modules.get_mut(index);
    artifact.code = code;
}

fn lower_one_module(modules: &const List<ProjectModule>, index: usize, companion: string, names: string): string ! ProjectBuildError {
    const artifact = &modules[index];
    const response = lower_module_cells_raw(artifact.code, artifact.module_path, companion, names) catch (code) {
        throw ProjectBuildError.module_lower;
    };
    return decode_cells(response) catch (code) {
        throw ProjectBuildError.module_lower;
    };
}

fn lower_managed_modules(graph: &const ComponentGraph, entries: &List<ModuleEntry>, modules: &List<ProjectModule>, targets: &const List<ManagedTarget>): void ! ProjectBuildError {
    var i: usize = 0;
    while i < targets.len() {
        const target = &targets[i];
        var first = true;
        var j: usize = 0;
        while j < i {
            if targets[j].source_path == target.source_path {
                first = false;
            }
            j = j + 1;
        }
        if first {
            var names = list<u8>();
            append(&names, "[");
            var comma = false;
            j = i;
            while j < targets.len() {
                const candidate = &targets[j];
                if candidate.source_path == target.source_path {
                    var seen = false;
                    var k: usize = i;
                    while k < j {
                        if targets[k].source_path == target.source_path and targets[k].name == candidate.name {
                            seen = true;
                        }
                        k = k + 1;
                    }
                    if not seen {
                        if comma {
                            append(&names, ",");
                        }
                        emit_string(candidate.name, &names);
                        comma = true;
                    }
                }
                j = j + 1;
            }
            append(&names, "]");
            var module_index: ?usize = none;
            j = 0;
            while j < modules.len() {
                if modules[j].source_path == target.source_path {
                    module_index = j;
                }
                j = j + 1;
            }
            if module_index is index {
                j = 0;
                while j < modules.len() {
                    if modules[j].module_path == target.publisher_path {
                        throw ProjectBuildError.module_collision;
                    }
                    j = j + 1;
                }
                const companion_name = basename(target.publisher_path);
                const companion = $"./{companion_name}";
                const lowered = try lower_one_module(modules, index, companion, string.from(names.view()));
                const final = rewrite_module_imports(lowered, entries, graph, target.module_path, target.source_path, false) catch (code) {
                    throw ProjectBuildError.module_analysis;
                };
                replace_module_code(modules, index, final);
                const publisher_code = rewrite_module_imports("import {createModuleState} from 'weiv:cells'; export const moduleState=createModuleState();", entries, graph, target.publisher_path, target.source_path, false) catch (code) {
                    throw ProjectBuildError.module_analysis;
                };
                modules.push(ProjectModule {
                    source_path: $"{target.source_path}#publisher",
                    module_path: string.from(target.publisher_path.bytes()),
                    code: publisher_code,
                    css: ""
                });
            } else {
                throw ProjectBuildError.module_lower;
            }
        }
        i = i + 1;
    }
    return;
}

fn append_managed_warnings(component: &const ComponentUnit, targets: &const List<ManagedTarget>, first_target: usize, diagnostics: &List<ProjectDiagnostic>): void {
    const sfc = component.sfc_document;
    const bindings = &component.template_bindings;
    var target_index = first_target;
    while target_index < targets.len() {
        const target = &targets[target_index];
        if target.unverified_assignment {
            var referenced = false;
            var expression_index: usize = 0;
            var expression_start: usize = 0;
            while expression_index < bindings.expressions.len() and not referenced {
                const expression = &bindings.expressions[expression_index];
                var reference_index: usize = 0;
                while reference_index < expression.references.len() {
                    if expression.references[reference_index].name == target.binding {
                        referenced = true;
                        expression_start = expression.source.start;
                    }
                    reference_index = reference_index + 1;
                }
                expression_index = expression_index + 1;
            }
            if referenced {
                const start = sfc.template.content_span.start + expression_start;
                diagnostics.push(ProjectDiagnostic {
                    code: "reactivity.unverified_dependency",
                    severity: "warning",
                    stage: "binding",
                    message: $"Weiv cannot verify reactive updates for this dependency: assigned value comes from a local or parameter whose ownership is unverified. Dependency: {component.source_path}::{target.binding} -> {target.source_path}::{target.name} -> incoming. Use an explicit observable or subscription adapter. This dependency crosses an unverified ownership or notification boundary.",
                    source_path: component.source_path,
                    span: Span {
                        start: start,
                        end: start + 1
                    },
                    location: location(component.source, start),
                    fatal: false
                });
            }
        }
        target_index = target_index + 1;
    }
}

struct SourceReference {
    source: string;
    span: Span;
}

fn decode_reference(value: &const Value): SourceReference ! ScriptDecodeError {
    return switch value {
        .object(record) => SourceReference {
            source: try validation.text_field(&record, "source"),
            span: try validation.span(&record, "span_start", "span_end")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn references(source: string, path: string): List<SourceReference> !ProjectBuildError {
    const raw = analyze_module_state_raw(source, path) catch (code) {
        throw ProjectBuildError.module_analysis;
    };
    const value = json.parse(raw) catch (code) {
        throw ProjectBuildError.module_analysis;
    };
    return switch value {
        .object(object) => validation.record_field<SourceReference>(&object, "sources", decode_reference) catch (code) {
            throw ProjectBuildError.module_analysis;
        };
        _ => {
            throw ProjectBuildError.module_analysis;
        }
    };
}

fn add_local_module(graph: &const ComponentGraph, entries: &List<ModuleEntry>, modules: &List<ProjectModule>, source_path: string, source: string): void ! ProjectBuildError {
    const bytes = source.bytes();
    if (mem.starts_with(bytes, "./".bytes()) or mem.starts_with(bytes, "../".bytes())) {
        if mem.ends_with(bytes, ".weiv".bytes()) {
            return;
        }
        const path = resolve_local(source_path, source) catch (code) {
            throw ProjectBuildError.module_path_invalid;
        };
        if not is_script_module(path) {
            return;
        }
        const module_index = register(entries, path) catch (code) {
            throw ProjectBuildError.module_collision;
        };
        const entry = &entries[module_index];
        const output = string.from(entry.output.bytes());
        var found = false;
        var j: usize = 0;
        while j < modules.len() {
            const artifact = &modules[j];
            if artifact.source_path == path {
                found = true;
            }
            j = j + 1;
        }
        if not found {
            const source_code = fs.read_file(path) catch (code) {
                throw ProjectBuildError.module_read_failure;
            };
            var code = source_code;
            if mem.ends_with(path.bytes(), ".ts".bytes()) or mem.ends_with(path.bytes(), ".mts".bytes()) {
                code = transpile_module_raw(source_code, path) catch (error) {
                    throw ProjectBuildError.module_transpile;
                };
            }
            const emitted = rewrite_module_imports(code, entries, graph, output, path, true) catch (code) {
                throw ProjectBuildError.module_analysis;
            };
            modules.push(ProjectModule {
                source_path: path,
                module_path: output,
                code: emitted,
                css: ""
            });
        }
    }
    return;
}

fn add_local_modules(graph: &const ComponentGraph, entries: &List<ModuleEntry>, modules: &List<ProjectModule>, source_path: string, script: &const ScriptFacts): void ! ProjectBuildError {
    var i: usize = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if should_preserve(record, script) {
            try add_local_module(graph, entries, modules, source_path, record.source);
        }
        i = i + 1;
    }
    return;
}

fn add_nested_modules(graph: &const ComponentGraph, entries: &List<ModuleEntry>, modules: &List<ProjectModule>): void ! ProjectBuildError {
    var i: usize = 0;
    while i < modules.len() {
        const artifact = &modules[i];
        const artifact_path = string.from(artifact.source_path.bytes());
        if mem.ends_with(artifact_path.bytes(), ".mjs".bytes()) or mem.ends_with(artifact_path.bytes(), ".js".bytes()) or mem.ends_with(artifact_path.bytes(), ".ts".bytes()) or mem.ends_with(artifact_path.bytes(), ".mts".bytes()) {
            const original = fs.read_file(artifact_path) catch (code) {
                throw ProjectBuildError.module_read_failure;
            };
            const sources = try references(original, artifact_path);
            var j: usize = 0;
            while j < sources.len() {
                const record = &sources[j];
                try add_local_module(graph, entries, modules, artifact_path, record.source);
                j = j + 1;
            }
        }
        i = i + 1;
    }
    return;
}

fn manifest(source: string): SlotManifest ! ProjectBuildError {
    const sfc = parse_sfc(source.bytes()) catch (code) {
        throw ProjectBuildError.invalid_component;
    };
    const bytes = source.bytes();
    const span = sfc.template.content_span;
    const template = bytes[span.start..span.end];
    const raw = parse_template(template) catch (code) {
        throw ProjectBuildError.invalid_component;
    };
    const normalized = normalize(&raw) catch (code) {
        throw ProjectBuildError.invalid_component;
    };
    const report = build_slot_manifest(template, &raw, &normalized);
    var entries = list<SlotEntry>();
    var i: usize = 0;
    while i < report.manifest.entries.len() {
        const entry = &report.manifest.entries[i];
        var name: ?string = none;
        if entry.name is text {
            name = string.from(text.bytes());
        }
        entries.push(SlotEntry {
            name: name,
            span: entry.span
        });
        i = i + 1;
    }
    return SlotManifest {
        entries: entries
    };
}

pub fn component_manifests(graph: &const ComponentGraph, path: string): ComponentManifests ! ProjectBuildError {
    var manifests: ComponentManifests = {
        entries: list<ComponentSlotManifest>()
    };
    var edge: usize = 0;
    while edge < graph.imports.len() {
        const imported = &graph.imports[edge];
        if imported.importer_path == path {
            const target = graph.find_node(imported.target_path);
            if target is index {
                const child = &graph.nodes[index];
                manifests.entries.push(ComponentSlotManifest {
                    tag_name: string.from(imported.local_name.bytes()),
                    manifest: try manifest(child.source)
                });
            } else {
                throw ProjectBuildError.missing_import;
            }
        }
        edge = edge + 1;
    }
    return manifests;
}

pub fn build(graph: &const ComponentGraph): ProjectBuild ! ProjectBuildError {
    var modules = list<ProjectModule>();
    var entries = list<ModuleEntry>();
    var managed_targets = list<ManagedTarget>();
    var diagnostics = list<ProjectDiagnostic>();
    var stylesheet = list<u8>();
    var i: usize = 0;
    while i < graph.nodes.len() {
        const first_target = managed_targets.len();
        const node = &graph.nodes[i];
        const manifests = try component_manifests(graph, node.path);
        var report = compile_report(node.source, node.path, &manifests);
        const unit = take_unit(&report) catch (code) {
            throw ProjectBuildError.compile_failure;
        };
        const browser = build_browser(unit);
        var overrides = list<ImportOverride>();
        var selection = empty_selection();
        select_local(&browser, &selection);
        select_managed(&browser, node.module_path, graph.root_dir, &selection, &managed_targets, &entries, &diagnostics) catch (code) {
            if code == .ambiguous_export {
                throw ProjectBuildError.ambiguous_managed_export;
            }
            throw ProjectBuildError.managed_selection;
        };
        append_managed_warnings(&browser.unit, &managed_targets, first_target, &diagnostics);
        var import_index: usize = 0;
        while import_index < browser.unit.script.facts.imports.len() {
            const record = &browser.unit.script.facts.imports[import_index];
            if should_preserve(record, &browser.unit.script.facts) {
                const target = mapped(&entries, graph, node.module_path, node.path, record.source, true) catch (code) {
                    throw ProjectBuildError.module_path_invalid;
                };
                overrides.push(ImportOverride {
                    source: string.from(record.source.bytes()),
                    target: target
                });
            }
            import_index = import_index + 1;
        }
        const artifact = emit_with_selection(&browser, &overrides, &selection) catch (code) {
            throw ProjectBuildError.emit_failure;
        };
        if artifact.css.bytes().len() > 0 {
            if stylesheet.len() > 0 {
                append(&stylesheet, "\n\n");
            }
            append(&stylesheet, artifact.css);
        }
        modules.push(ProjectModule {
            source_path: string.from(node.path.bytes()),
            module_path: string.from(node.module_path.bytes()),
            code: artifact.code,
            css: artifact.css
        });
        try add_local_modules(graph, &entries, &modules, node.path, &browser.unit.script.facts);
        i = i + 1;
    }
    try add_nested_modules(graph, &entries, &modules);
    try lower_managed_modules(graph, &entries, &modules, &managed_targets);
    const entry = graph.find_node(graph.entry_path);
    if entry is index {
        const entry_node = &graph.nodes[index];
        const entry_module = string.from(entry_node.module_path.bytes());
        const css = string.from(stylesheet.view());
        return ProjectBuild {
            entry_module: entry_module,
            modules: modules,
            stylesheet: css,
            diagnostics: diagnostics
        };
    }
    throw ProjectBuildError.invalid_component;
}
