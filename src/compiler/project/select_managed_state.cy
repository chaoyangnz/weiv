// Operation: direct imported module writes -> publisher-backed component subscriptions.
import { BrowserComponent } from .compiler.backend.browser.component;
import { CellSelection, ManagedSubscription } from .compiler.backend.browser.emit.cell_selection;
import { ModuleEntry, register, resolve_local } from .compiler.project.module_graph;
import { relative_output } from .compiler.project.output_paths;
import { analyze_module_state_raw } from .ffi.script_backend;
import { ProjectDiagnostic, location } from .compiler.project.diagnostics;
import { Span } from .compiler.source;
import std.fs;
import std.json;
import std.mem;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;

pub struct ManagedTarget {
    pub source_path: string;
    pub module_path: string;
    pub publisher_path: string;
    pub name: string;
    pub binding: string;
    pub unverified_assignment: bool;
}

pub enum ManagedSelectionError {
    invalid_path;
    read_failure;
    analysis_failure;
    ambiguous_export;
}

struct ExportRecord {
    exported: string;
    kind: string;
    local: ?string;
    source: ?string;
    imported: ?string;
}

struct PublishedLocal {
    found: bool;
    managed: bool;
    name: string;
    path: string;
    value_kind: string;
}

fn decode_text(value: &const Value): string ! ScriptDecodeError {
    return try validation.text(value);
}

fn decode_export(value: &const Value): ExportRecord ! ScriptDecodeError {
    return switch value {
        .object(object) => ExportRecord {
            exported: try validation.text_field(&object, "exported"),
            kind: try validation.text_field(&object, "kind"),
            local: try validation.optional_text_field(&object, "local"),
            source: try validation.optional_text_field(&object, "source"),
            imported: try validation.optional_text_field(&object, "imported")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

struct ExportLookup {
    path: string;
    name: string;
}

struct AssignmentValue {
    value_kind: string;
}

struct AssignmentRecord {
    target: string;
    inputs: List<string>;
    value: AssignmentValue;
}

struct DependencyBinding {
    name: string;
    declaration_kind: string;
    value_kind: string;
    reads: List<string>;
    calls: List<string>;
}

fn decode_dependency_binding(value: &const Value): DependencyBinding ! ScriptDecodeError {
    return switch value {
        .object(object) => DependencyBinding {
            name: try validation.text_field(&object, "name"),
            declaration_kind: try validation.text_field(&object, "declaration_kind"),
            value_kind: try validation.text_field(&object, "value_kind"),
            reads: try validation.record_field<string>(&object, "reads", decode_text),
            calls: try validation.record_field<string>(&object, "calls", decode_text)
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn has_dependency(targets: &const List<ManagedTarget>, path: string, name: string): bool {
    var i: usize = 0;
    while i < targets.len() {
        const target = &targets[i];
        if target.source_path == path and target.name == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn owned(root: string, path: string): bool {
    if not mem.starts_with(path.bytes(), root.bytes()) or path.bytes().len() <= root.bytes().len() {
        return false;
    }
    const next = path.bytes()[root.bytes().len()];
    return (next == 47 or next == 92) and
    mem.index_of(path.bytes(), "/node_modules/".bytes()) is none and
    mem.index_of(path.bytes(), "\\node_modules\\".bytes()) is none;
}

fn referenced_expression(component: &const BrowserComponent, binding: string): ?Span {
    const expressions = &component.unit.template_bindings.expressions;
    var i: usize = 0;
    while i < expressions.len() {
        const expression = &expressions[i];
        var j: usize = 0;
        while j < expression.references.len() {
            if expression.references[j].name == binding {
                const offset = component.unit.sfc_document.template.content_span.start;
                return Span {
                    start: offset + expression.source.start,
                    end: offset + expression.source.end
                };
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return none;
}

fn append_external_warning(component: &const BrowserComponent, binding: string, path: string, name: string, code: string, detail: string, diagnostics: &List<ProjectDiagnostic>): void {
    if referenced_expression(component, binding) is span {
        diagnostics.push(ProjectDiagnostic {
            code: code,
            severity: "warning",
            stage: "binding",
            message: detail,
            source_path: component.unit.source_path,
            span: span,
            location: location(component.unit.source, span.start),
            fatal: false
        });
    }
}

fn external_subscription_unverified(path: string, root: string): bool ! ManagedSelectionError {
    const source = fs.read_file(path) catch (code) {
        throw ManagedSelectionError.read_failure;
    };
    const raw = analyze_module_state_raw(source, path) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    const value = json.parse(raw) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    var bindings = list<DependencyBinding>();
    switch value {
        .object(object) => {
            bindings = validation.record_field<DependencyBinding>(&object, "bindings", decode_dependency_binding) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
        }
        _ => {
            throw ManagedSelectionError.analysis_failure;
        }
    }
    var pending = list<string>();
    pending.push(string.from(root.bytes()));
    var visited = list<string>();
    while pending.len() > 0 {
        const name = pending.pop();
        var seen = false;
        var i: usize = 0;
        while i < visited.len() {
            if visited[i] == name {
                seen = true;
            }
            i = i + 1;
        }
        if seen {
            continue;
        }
        visited.push(string.from(name.bytes()));
        i = 0;
        while i < bindings.len() {
            const binding = &bindings[i];
            if binding.name == name {
                for dependency in binding.reads {
                    var local = false;
                    var dependency_kind = "";
                    var j: usize = 0;
                    while j < bindings.len() {
                        if bindings[j].name == dependency {
                            local = true;
                            dependency_kind = bindings[j].value_kind;
                        }
                        j = j + 1;
                    }
                    if local and (dependency_kind == "observable" or dependency_kind == "snapshot") {
                        return true;
                    }
                    if local and dependency_kind == "function" {
                        pending.push(string.from(dependency.bytes()));
                    }
                }
            }
            i = i + 1;
        }
    }
    return false;
}

fn reflective_dependency(path: string, state_name: string): ?string ! ManagedSelectionError {
    const source = fs.read_file(path) catch (code) {
        throw ManagedSelectionError.read_failure;
    };
    const raw = analyze_module_state_raw(source, path) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    const value = json.parse(raw) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    var bindings = list<DependencyBinding>();
    switch value {
        .object(object) => {
            bindings = validation.record_field<DependencyBinding>(&object, "bindings", decode_dependency_binding) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
        }
        _ => {
            throw ManagedSelectionError.analysis_failure;
        }
    }
    var i: usize = 0;
    while i < bindings.len() {
        const binding = &bindings[i];
        if binding.value_kind == "function" {
            var reads_state = false;
            for dependency in binding.reads {
                if dependency == state_name {
                    reads_state = true;
                }
            }
            if reads_state {
                for call in binding.calls {
                    if call == "Reflect.apply" {
                        return string.from(call.bytes());
                    }
                }
            }
        }
        i = i + 1;
    }
    return none;
}

fn has_subscription(selection: &const CellSelection, binding: string, name: string): bool {
    var i: usize = 0;
    while i < selection.managed_subscriptions.len() {
        const subscription = &selection.managed_subscriptions[i];
        if subscription.binding == binding and subscription.name == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn add_managed_subscription(selection: &CellSelection, component_module: string, publisher: string, binding: string, name: string): void {
    if has_subscription(selection, binding, name) {
        return;
    }
    selection.managed_subscriptions.push(ManagedSubscription {
        specifier: relative_output(component_module, publisher),
        name: string.from(name.bytes()),
        binding: string.from(binding.bytes())
    });
}

fn add_dependency_closure(path: string, root: string, publisher: string, subscribe_dependencies: bool, selection: &CellSelection, component_module: string, subscription_binding: string, targets: &List<ManagedTarget>, entries: &List<ModuleEntry>): void ! ManagedSelectionError {
    const source = fs.read_file(path) catch (code) {
        throw ManagedSelectionError.read_failure;
    };
    const raw = analyze_module_state_raw(source, path) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    const value = json.parse(raw) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    var bindings = list<DependencyBinding>();
    switch value {
        .object(object) => {
            bindings = validation.record_field<DependencyBinding>(&object, "bindings", decode_dependency_binding) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
        }
        _ => {
            throw ManagedSelectionError.analysis_failure;
        }
    }
    var root_kind = "unknown";
    var root_index: usize = 0;
    while root_index < bindings.len() {
        if bindings[root_index].name == root {
            root_kind = bindings[root_index].value_kind;
        }
        root_index = root_index + 1;
    }
    var pending = list<ExportLookup>();
    pending.push(ExportLookup {
        path: string.from(path.bytes()),
        name: string.from(root.bytes())
    });
    var visited = list<ExportLookup>();
    while pending.len() > 0 {
        const lookup = pending.pop();
        var seen = false;
        var i: usize = 0;
        while i < visited.len() {
            if visited[i].name == lookup.name {
                seen = true;
            }
            i = i + 1;
        }
        if seen {
            continue;
        }
        visited.push(ExportLookup {
            path: string.from(lookup.path.bytes()),
            name: string.from(lookup.name.bytes())
        });
        var binding_index: ?usize = none;
        i = 0;
        while i < bindings.len() {
            if bindings[i].name == lookup.name {
                binding_index = i;
            }
            i = i + 1;
        }
        if binding_index is index {
            const binding = &bindings[index];
            for dependency in binding.reads {
                var local = false;
                i = 0;
                while i < bindings.len() {
                    if bindings[i].name == dependency {
                        local = true;
                    }
                    i = i + 1;
                }
                if not local {
                    continue;
                }
                var dependency_kind = "unknown";
                i = 0;
                while i < bindings.len() {
                    if bindings[i].name == dependency {
                        dependency_kind = bindings[i].value_kind;
                    }
                    i = i + 1;
                }
                const unverified = dependency_kind != "function" and try assignment_unverified(path, dependency);
                if subscribe_dependencies and dependency_kind != "function" and not unverified and (lookup.name != root or root_kind != "destructured") {
                    add_managed_subscription(selection, component_module, publisher, subscription_binding, dependency);
                }
                if dependency_kind != "function" and not unverified and not has_dependency(targets, path, dependency) {
                    const module_index = register(entries, path) catch (code) {
                        throw ManagedSelectionError.invalid_path;
                    };
                    const entry = &entries[module_index];
                    targets.push(ManagedTarget {
                        source_path: string.from(path.bytes()),
                        module_path: string.from(entry.output.bytes()),
                        publisher_path: string.from(entry.publisher.bytes()),
                        name: string.from(dependency.bytes()),
                        binding: string.from(dependency.bytes()),
                        unverified_assignment: false
                    });
                }
                pending.push(ExportLookup {
                    path: string.from(path.bytes()),
                    name: string.from(dependency.bytes())
                });
            }
        }
    }
}

fn decode_assignment_value(value: &const Value): AssignmentValue ! ScriptDecodeError {
    return switch value {
        .object(object) => AssignmentValue {
            value_kind: try validation.text_field(&object, "value_kind")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_assignment(value: &const Value): AssignmentRecord ! ScriptDecodeError {
    return switch value {
        .object(object) => AssignmentRecord {
            target: try validation.text_field(&object, "target"),
            inputs: try validation.record_field<string>(&object, "inputs", decode_text),
            value: try decode_assignment_value(try validation.required(&object, "value"))
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn assignment_unverified(path: string, name: string): bool ! ManagedSelectionError {
    const published = try published_local(path, name);
    var source_path = path;
    var local_name = name;
    if published.found {
        source_path = published.path;
        local_name = published.name;
    }
    const source = fs.read_file(source_path) catch (code) {
        throw ManagedSelectionError.read_failure;
    };
    const raw = analyze_module_state_raw(source, source_path) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    const value = json.parse(raw) catch (code) {
        throw ManagedSelectionError.analysis_failure;
    };
    switch value {
        .object(object) => {
            const assignments = validation.record_field<AssignmentRecord>(&object, "assignments", decode_assignment) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
            var i: usize = 0;
            while i < assignments.len() {
                const assignment = &assignments[i];
                if assignment.target == local_name and
                (assignment.inputs.len() > 0 or assignment.value.value_kind == "input") {
                    return true;
                }
                i = i + 1;
            }
        }
        _ => {
            throw ManagedSelectionError.analysis_failure;
        }
    }
    return false;
}

fn published_local(path: string, name: string): PublishedLocal ! ManagedSelectionError {
    var pending = list<ExportLookup>();
    pending.push(ExportLookup {
        path: string.from(path.bytes()),
        name: string.from(name.bytes())
    });
    var visited = list<ExportLookup>();
    var owner_path = string.from("".bytes());
    var owner_name = string.from("".bytes());
    var owner_managed = false;
    var owner_value_kind = string.from("".bytes());
    var found = false;
    var ambiguous = false;
    while pending.len() > 0 {
        const lookup = pending.pop();
        var seen = false;
        var j: usize = 0;
        while j < visited.len() {
            const earlier = &visited[j];
            if earlier.path == lookup.path and earlier.name == lookup.name {
                seen = true;
            }
            j = j + 1;
        }
        if not seen {
            visited.push(ExportLookup {
                path: string.from(lookup.path.bytes()),
                name: string.from(lookup.name.bytes())
            });
            const source = fs.read_file(lookup.path) catch (code) {
                throw ManagedSelectionError.read_failure;
            };
            const raw = analyze_module_state_raw(source, lookup.path) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
            const value = json.parse(raw) catch (code) {
                throw ManagedSelectionError.analysis_failure;
            };
            switch value {
                .object(object) => {
                    const ok = validation.bool_field(&object, "ok") catch (code) {
                        throw ManagedSelectionError.analysis_failure;
                    };
                    if not ok {
                        throw ManagedSelectionError.analysis_failure;
                    }
                    const writes = validation.record_field<string>(&object, "root_writes", decode_text) catch (code) {
                        throw ManagedSelectionError.analysis_failure;
                    };
                    const exports = validation.record_field<ExportRecord>(&object, "exports", decode_export) catch (code) {
                        throw ManagedSelectionError.analysis_failure;
                    };
                    const bindings = validation.record_field<DependencyBinding>(&object, "bindings", decode_dependency_binding) catch (code) {
                        throw ManagedSelectionError.analysis_failure;
                    };
                    const dynamic_access = validation.bool_field(&object, "dynamic_access") catch (code) {
                        throw ManagedSelectionError.analysis_failure;
                    };
                    var explicit = false;
                    var i: usize = 0;
                    while i < exports.len() {
                        const record = &exports[i];
                        if record.exported == lookup.name and record.kind == "local" {
                            explicit = true;
                            if record.local is local {
                                var managed_value = false;
                                var has_binding = false;
                                var binding_index: usize = 0;
                                while binding_index < bindings.len() {
                                    const binding = &bindings[binding_index];
                                    if binding.name == local {
                                        has_binding = true;
                                        owner_value_kind = string.from(binding.value_kind.bytes());
                                        if (binding.declaration_kind == "let" or binding.declaration_kind == "const") and
                                        binding.value_kind != "function" and binding.value_kind != "class" and not dynamic_access {
                                            managed_value = true;
                                        }
                                    }
                                    binding_index = binding_index + 1;
                                }
                                if has_binding {
                                    if found and (owner_path != lookup.path or owner_name != local) {
                                        ambiguous = true;
                                    }
                                    owner_path = string.from(lookup.path.bytes());
                                    owner_name = string.from(local.bytes());
                                    owner_managed = managed_value;
                                    found = true;
                                }
                                for item in writes {
                                    if item == local {
                                        if found and (owner_path != lookup.path or owner_name != local) {
                                            ambiguous = true;
                                        }
                                        owner_path = string.from(lookup.path.bytes());
                                        owner_name = string.from(local.bytes());
                                        owner_managed = true;
                                        owner_value_kind = "object";
                                        found = true;
                                    }
                                }
                            }
                        }
                        if record.exported == lookup.name and record.kind == "reexport" {
                            explicit = true;
                            if record.source is specifier {
                                if record.imported is imported {
                                    const target = resolve_local(lookup.path, specifier) catch (code) {
                                        throw ManagedSelectionError.invalid_path;
                                    };
                                    pending.push(ExportLookup {
                                        path: target,
                                        name: string.from(imported.bytes())
                                    });
                                }
                            }
                        }
                        i = i + 1;
                    }
                    if not explicit and lookup.name != "default" {
                        i = 0;
                        while i < exports.len() {
                            const record = &exports[i];
                            if record.kind == "star" {
                                if record.source is specifier {
                                    const target = resolve_local(lookup.path, specifier) catch (code) {
                                        throw ManagedSelectionError.invalid_path;
                                    };
                                    pending.push(ExportLookup {
                                        path: target,
                                        name: string.from(lookup.name.bytes())
                                    });
                                }
                            }
                            i = i + 1;
                        }
                    }
                }
                _ => {
                    throw ManagedSelectionError.analysis_failure;
                }
            }
        }
    }
    if ambiguous {
        throw ManagedSelectionError.ambiguous_export;
    }
    if not found {
        return PublishedLocal {
            found: false,
            managed: false,
            name: "",
            path: "",
            value_kind: ""
        };
    }
    return PublishedLocal {
        found: true,
        managed: owner_managed,
        name: owner_name,
        path: owner_path,
        value_kind: owner_value_kind
    };
}

fn exported_names(path: string): List<string> !ManagedSelectionError {
    var output = list<string>();
    var pending = list<string>();
    pending.push(string.from(path.bytes()));
    var visited = list<string>();
    while pending.len() > 0 {
        const current = pending.pop();
        var seen = false;
        var i: usize = 0;
        while i < visited.len() {
            if visited[i] == current {
                seen = true;
            }
            i = i + 1;
        }
        if seen {
            continue;
        }
        visited.push(string.from(current.bytes()));
        const source = fs.read_file(current) catch (code) {
            throw ManagedSelectionError.read_failure;
        };
        const raw = analyze_module_state_raw(source, current) catch (code) {
            throw ManagedSelectionError.analysis_failure;
        };
        const value = json.parse(raw) catch (code) {
            throw ManagedSelectionError.analysis_failure;
        };
        switch value {
            .object(object) => {
                const exports = validation.record_field<ExportRecord>(&object, "exports", decode_export) catch (code) {
                    throw ManagedSelectionError.analysis_failure;
                };
                i = 0;
                while i < exports.len() {
                    const record = &exports[i];
                    if record.kind == "star" {
                        if record.source is specifier {
                            pending.push(resolve_local(current, specifier) catch (code) {
                                throw ManagedSelectionError.invalid_path;
                            });
                        }
                    } else {
                        var duplicate = false;
                        var j: usize = 0;
                        while j < output.len() {
                            if output[j] == record.exported {
                                duplicate = true;
                            }
                            j = j + 1;
                        }
                        if not duplicate {
                            output.push(string.from(record.exported.bytes()));
                        }
                    }
                    i = i + 1;
                }
            }
            _ => {
                throw ManagedSelectionError.analysis_failure;
            }
        }
    }
    return output;
}

fn mark_publisher(selection: &CellSelection, index: usize): void {
    const subscription = selection.local_subscriptions.get_mut(index);
    subscription.publisher_backed = true;
}

pub fn select_into(component: &const BrowserComponent, component_module: string, managed_root: string, selection: &CellSelection, targets: &List<ManagedTarget>, entries: &List<ModuleEntry>, diagnostics: &List<ProjectDiagnostic>): void ! ManagedSelectionError {
    const script = &component.unit.script.facts;
    var i: usize = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if record.kind == "namespace" and
        (mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes())) and
        not mem.ends_with(record.source.bytes(), ".weiv".bytes()) {
            var selected: ?usize = none;
            var j: usize = 0;
            while j < selection.local_subscriptions.len() {
                if selection.local_subscriptions[j].name == record.local_name {
                    selected = j;
                }
                j = j + 1;
            }
            if selected is index {
                const path = resolve_local(component.unit.source_path, record.source) catch (code) {
                    throw ManagedSelectionError.invalid_path;
                };
                const names = try exported_names(path);
                var subscribed = false;
                j = 0;
                while j < names.len() {
                    const published = try published_local(path, names[j]);
                    if published.found {
                        const managed = published.managed and owned(managed_root, published.path);
                        if not managed and
                        published.value_kind != "function" and published.value_kind != "class" and
                        published.value_kind != "observable" and published.value_kind != "snapshot" {
                            append_external_warning(component, record.local_name, published.path, published.name, "reactivity.untracked_external_state", $"External state {published.path}::{published.name} has no observable or subscription adapter. Weiv cannot prove that changes through {record.local_name} notify this component. Move the state into the project, wrap it with weiv:observable, or expose an explicit subscription adapter.", diagnostics);
                        }
                        const module_index = register(entries, published.path) catch (code) {
                            throw ManagedSelectionError.invalid_path;
                        };
                        const entry = &entries[module_index];
                        const publisher = string.from(entry.publisher.bytes());
                        if managed {
                            add_managed_subscription(selection, component_module, publisher, record.local_name, published.name);
                            subscribed = true;
                            if not has_dependency(targets, published.path, published.name) {
                                targets.push(ManagedTarget {
                                    source_path: published.path,
                                    module_path: string.from(entry.output.bytes()),
                                    publisher_path: publisher,
                                    name: string.from(published.name.bytes()),
                                    binding: string.from(record.local_name.bytes()),
                                    unverified_assignment: try assignment_unverified(published.path, published.name)
                                });
                            }
                            try add_dependency_closure(published.path, published.name, publisher, true, selection, component_module, record.local_name, targets, entries);
                        }
                    }
                    j = j + 1;
                }
                if subscribed {
                    mark_publisher(selection, index);
                }
            }
        }
        if record.imported_name is imported {
            if record.kind == "named" and
            (mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes())) and
            not mem.ends_with(record.source.bytes(), ".weiv".bytes()) {
                var selected: ?usize = none;
                var j: usize = 0;
                while j < selection.local_subscriptions.len() {
                    if selection.local_subscriptions[j].name == record.local_name {
                        selected = j;
                    }
                    j = j + 1;
                }
                if selected is index {
                    const path = resolve_local(component.unit.source_path, record.source) catch (code) {
                        throw ManagedSelectionError.invalid_path;
                    };
                    const published = try published_local(path, imported);
                    if published.found {
                        const local = published.name;
                        if not owned(managed_root, published.path) or not published.managed {
                            if published.value_kind != "function" and published.value_kind != "class" and
                            published.value_kind != "observable" and published.value_kind != "snapshot" {
                                append_external_warning(component, record.local_name, published.path, local, "reactivity.untracked_external_state", $"External state {published.path}::{local} has no observable or subscription adapter. Weiv cannot prove that changes to {record.local_name} notify this component. Move the state into the project, wrap it with weiv:observable, or expose an explicit subscription adapter.", diagnostics);
                            } else if published.value_kind == "function" and try external_subscription_unverified(published.path, local) {
                                append_external_warning(component, record.local_name, published.path, local, "reactivity.unverified_dependency", $"External helper {published.path}::{local} has a subscription path that Weiv cannot verify. Use an explicit observable or subscription adapter so updates cross the helper boundary.", diagnostics);
                            }
                        }
                        const module_index = register(entries, published.path) catch (code) {
                            throw ManagedSelectionError.invalid_path;
                        };
                        const entry = &entries[module_index];
                        const emitted_path = string.from(entry.output.bytes());
                        const publisher = string.from(entry.publisher.bytes());
                        const managed = published.managed and owned(managed_root, published.path);
                        if managed {
                            const local_publisher = relative_output(component_module, publisher);
                            mark_publisher(selection, index);
                            const reflection = try reflective_dependency(published.path, local);
                            if reflection is call {
                                append_external_warning(component, record.local_name, published.path, local, "reactivity.unverified_dependency", $"Managed state {published.path}::{local} reaches {call} with a reflected assignment destination. Weiv can preserve ordinary writes, but the reflected ownership and subscription path is unverified. Use a direct mutation function or an explicit observable or subscription adapter.", diagnostics);
                            }
                            selection.managed_subscriptions.push(ManagedSubscription {
                                specifier: local_publisher,
                                name: string.from(local.bytes()),
                                binding: string.from(record.local_name.bytes())
                            });
                            targets.push(ManagedTarget {
                                source_path: published.path,
                                module_path: emitted_path,
                                publisher_path: publisher,
                                name: string.from(local.bytes()),
                                binding: string.from(record.local_name.bytes()),
                                unverified_assignment: try assignment_unverified(published.path, local)
                            });
                            try add_dependency_closure(published.path, local, publisher, true, selection, component_module, record.local_name, targets, entries);
                        } else if published.value_kind == "function" and owned(managed_root, published.path) {
                            mark_publisher(selection, index);
                            try add_dependency_closure(published.path, local, publisher, true, selection, component_module, record.local_name, targets, entries);
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    return;
}
