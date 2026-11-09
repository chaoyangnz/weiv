// Operation: component template ownership -> warning-only reactive boundary diagnostics.
import { ComponentUnit } from .compiler.component_unit;
import { ProjectDiagnostic, location } from .compiler.project.diagnostics;
import { resolve_local } from .compiler.project.module_graph;
import { LirDocument } from .compiler.lower.lir;
import { analyze_module_state_raw } from .ffi.script_backend;
import { Span } from .compiler.source;
import { basename } from std.path;
import std.fs;
import std.json;
import std.mem;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;

struct BindingFacts {
    name: string;
    declaration_kind: string;
    value_kind: string;
    alias: ?string;
    factory: ?string;
    reads: List<string>;
    calls: List<string>;
    globals: List<string>;
    has_mutation: bool;
    retained_local_state: bool;
}

struct ExportFacts {
    exported: string;
    kind: string;
    local: ?string;
    source: ?string;
    imported: ?string;
}

struct ImportFacts {
    local: string;
    imported: string;
    source: string;
}

struct AssignmentFacts {
    target: string;
    path: ?string;
    dynamic_path: bool;
    operator: string;
    projected: bool;
    inputs: List<string>;
    value: BindingFacts;
}

struct ArgumentFlowFacts {
    target: string;
    callee: string;
    spread: bool;
    indirect: bool;
    argument_index: usize;
}

struct Facts {
    ok: bool;
    bindings: List<BindingFacts>;
    exports: List<ExportFacts>;
    imports: List<ImportFacts>;
    root_writes: List<string>;
    assignments: List<AssignmentFacts>;
    argument_flows: List<ArgumentFlowFacts>;
    dynamic_access: bool;
}

struct Origin {
    found: bool;
    verified: bool;
    external: bool;
    path: string;
    name: string;
    kind: string;
    via: string;
    reason: string;
}

fn decode_text(value: &const Value): string ! ScriptDecodeError {
    return try validation.text(value);
}

fn decode_binding(value: &const Value): BindingFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => BindingFacts {
            name: try validation.text_field(&object, "name"),
            declaration_kind: try validation.text_field(&object, "declaration_kind"),
            value_kind: try validation.text_field(&object, "value_kind"),
            alias: try validation.optional_text_field(&object, "alias"),
            factory: try validation.optional_text_field(&object, "factory"),
            reads: try validation.record_field<string>(&object, "reads", decode_text),
            calls: try validation.record_field<string>(&object, "calls", decode_text),
            globals: try validation.record_field<string>(&object, "globals", decode_text),
            has_mutation: try validation.bool_field(&object, "has_mutation"),
            retained_local_state: try validation.bool_field(&object, "retained_local_state")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_export(value: &const Value): ExportFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => ExportFacts {
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

fn decode_import(value: &const Value): ImportFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => ImportFacts {
            local: try validation.text_field(&object, "local"),
            imported: try validation.text_field(&object, "imported"),
            source: try validation.text_field(&object, "source")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_assignment(value: &const Value): AssignmentFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => AssignmentFacts {
            target: try validation.text_field(&object, "target"),
            path: try validation.optional_text_field(&object, "path"),
            dynamic_path: try validation.bool_field(&object, "dynamic_path"),
            operator: try validation.text_field(&object, "operator"),
            projected: try validation.bool_field(&object, "projected"),
            inputs: try validation.record_field<string>(&object, "inputs", decode_text),
            value: try decode_binding(try validation.required(&object, "value"))
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn decode_argument_flow(value: &const Value): ArgumentFlowFacts ! ScriptDecodeError {
    return switch value {
        .object(object) => ArgumentFlowFacts {
            target: try validation.text_field(&object, "target"),
            callee: try validation.text_field(&object, "callee"),
            spread: try validation.bool_field(&object, "spread"),
            indirect: try validation.bool_field(&object, "indirect"),
            argument_index: try validation.unsigned(try validation.required(&object, "argument_index"), validation.offset_limit())
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn facts(path: string): ?Facts {
    const source = fs.read_file(path) catch (code) {
        return none;
    };
    return facts_from_source(source, path);
}

fn facts_from_source(source: string, path: string): ?Facts {
    const raw = analyze_module_state_raw(source, path) catch (code) {
        return none;
    };
    const value = json.parse(raw) catch (code) {
        return none;
    };
    if value is .object(object) {
        const result: Facts = {
            ok: validation.bool_field(&object, "ok") catch (code) => false,
            bindings: validation.record_field<BindingFacts>(&object, "bindings", decode_binding) catch (code) => list<BindingFacts>(),
            exports: validation.record_field<ExportFacts>(&object, "exports", decode_export) catch (code) => list<ExportFacts>(),
            imports: validation.record_field<ImportFacts>(&object, "imports", decode_import) catch (code) => list<ImportFacts>(),
            root_writes: validation.record_field<string>(&object, "root_writes", decode_text) catch (code) => list<string>(),
            assignments: validation.record_field<AssignmentFacts>(&object, "assignments", decode_assignment) catch (code) => list<AssignmentFacts>(),
            argument_flows: validation.record_field<ArgumentFlowFacts>(&object, "argument_flows", decode_argument_flow) catch (code) => list<ArgumentFlowFacts>(),
            dynamic_access: validation.bool_field(&object, "dynamic_access") catch (code) => false
        };
        const present: ?Facts = result;
        return present;
    }
    return none;
}

fn component_facts(unit: &const ComponentUnit): ?Facts {
    const span = unit.sfc_document.script.content_span;
    const source = string.from(unit.source.bytes()[span.start..span.end]);
    return facts_from_source(source, unit.source_path);
}

fn binding(facts_value: &const Facts, name: string): ?usize {
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        if facts_value.bindings[i].name == name {
            return i;
        }
        i = i + 1;
    }
    return none;
}

fn seen(visited: &const List<string>, value: string): bool {
    var i: usize = 0;
    while i < visited.len() {
        if visited[i] == value {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn list_has(values: &const List<string>, value: string): bool {
    var i: usize = 0;
    while i < values.len() {
        if values[i] == value {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn count_sequence(value: string, needle: string): usize {
    const bytes = value.bytes();
    const target = needle.bytes();
    if target.len() == 0 or target.len() > bytes.len() {
        return 0;
    }
    var count: usize = 0;
    var i: usize = 0;
    while i + target.len() <= bytes.len() {
        if mem.starts_with(bytes[i..], target) {
            count = count + 1;
            i = i + target.len();
        } else {
            i = i + 1;
        }
    }
    return count;
}

fn pop_discard(values: &List<string>): void {
    const _ = values.pop();
}

fn trace(via: string, path: string): string {
    if via.bytes().len() == 0 {
        return basename(path);
    }
    const path_name = basename(path);
    return $"{via} -> {path_name}";
}

fn factory_kind(path: string, module_facts: &const Facts, maybe_factory: ?string, via: string, visited: &List<string>): string {
    if maybe_factory is factory {
        if mem.index_of(factory.bytes(), ".".bytes()) is factory_dot_at {
            const factory_root = string.from(factory.bytes()[0..factory_dot_at]);
            const factory_member = string.from(factory.bytes()[factory_dot_at + 1..]);
            var namespace_import_index: usize = 0;
            while namespace_import_index < module_facts.imports.len() {
                const record = &module_facts.imports[namespace_import_index];
                if record.local == factory_root and
                (mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes())) {
                    const target = resolve_local(path, record.source) catch (code) {
                        namespace_import_index = namespace_import_index + 1;
                        continue;
                    };
                    const namespace_facts = facts(target);
                    if namespace_facts is target_value {
                        var export_index: usize = 0;
                        while export_index < target_value.exports.len() {
                            const exported = &target_value.exports[export_index];
                            if exported.exported == record.imported and exported.kind == "namespace_reexport" {
                                if exported.source is source {
                                    if source == "weiv:observable" and (factory_member == "observable" or factory_member == "snapshot") {
                                        return string.from(factory_member.bytes());
                                    }
                                }
                            }
                            export_index = export_index + 1;
                        }
                    }
                }
                namespace_import_index = namespace_import_index + 1;
            }
        }
        var import_index: usize = 0;
        while import_index < module_facts.imports.len() {
            const record = &module_facts.imports[import_index];
            if record.local == factory {
                if record.source == "weiv:observable" and (record.imported == "observable" or record.imported == "snapshot") {
                    return string.from(record.imported.bytes());
                }
                if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                    const target = resolve_local(path, record.source) catch (code) {
                        import_index = import_index + 1;
                        continue;
                    };
                    const factory_origin = resolve_export(target, record.imported, trace(trace(via, path), target), visited);
                    if not factory_origin.verified {
                        return "unknown";
                    }
                    return string.from(factory_origin.kind.bytes());
                }
            }
            import_index = import_index + 1;
        }
    }
    return "";
}

fn local_origin(path: string, name: string, via: string, visited: &List<string>): Origin {
    const key = $"local:{path}#{name}";
    if seen(visited, key) {
        return Origin {
            found: true,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "cyclic dependency coverage is unresolved"
        };
    }
    visited.push(key);
    defer pop_discard(visited);
    const module_facts = facts(path);
    if module_facts is none {
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "module analysis failed"
        };
    }
    if not module_facts.ok {
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "module analysis failed"
        };
    }
    const module_source = fs.read_file(path) catch (code) {
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "module source cannot be read for boundary analysis"
        };
    };
    if module_source.bytes().len() >= 1000000 {
        return Origin {
            found: true,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "module exceeds the boundary-analysis size limit"
        };
    }
    var i: usize = 0;
    while i < module_facts.imports.len() {
        const record = &module_facts.imports[i];
        if record.local == name {
            if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                const target = resolve_local(path, record.source) catch (code) {
                    i = i + 1;
                    continue;
                };
                return resolve_export(target, record.imported, trace(trace(via, path), target), visited);
            }
            if record.source == "weiv:observable" and (record.imported == "observable" or record.imported == "snapshot") {
                return Origin {
                    found: true,
                    verified: true,
                    external: true,
                    path: record.source,
                    name: name,
                    kind: record.imported,
                    via: trace(trace(via, path), path),
                    reason: ""
                };
            }
            return Origin {
                found: true,
                verified: false,
                external: true,
                path: record.source,
                name: name,
                kind: "external",
                via: trace(trace(via, path), path),
                reason: "package export has no verified notification contract"
            };
        }
        i = i + 1;
    }
    if module_facts.dynamic_access or list_has(&module_facts.root_writes, name) {
        if binding(&module_facts, name) is unstable_index {
            const unstable = &module_facts.bindings[unstable_index];
            if unstable.value_kind == "observable" or unstable.value_kind == "snapshot" {
                return Origin {
                    found: true,
                    verified: false,
                    external: false,
                    path: path,
                    name: name,
                    kind: string.from(unstable.value_kind.bytes()),
                    via: via,
                    reason: "observable state has dynamic access or root replacement outside its notification path"
                };
            }
        }
        return Origin {
            found: true,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "dynamic access or root replacement has no verified notification path"
        };
    }
    const maybe_index = binding(&module_facts, name);
    if maybe_index is none {
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "export was not resolved"
        };
    }
    const value = &module_facts.bindings[maybe_index];
    var kind = string.from(value.value_kind.bytes());
    const resolved_factory_kind = factory_kind(path, &module_facts, value.factory, via, visited);
    if resolved_factory_kind.bytes().len() > 0 {
        kind = resolved_factory_kind;
    }
    return Origin {
        found: true,
        verified: true,
        external: false,
        path: path,
        name: name,
        kind: kind,
        via: via,
        reason: ""
    };
}

fn resolve_export(path: string, name: string, via: string, visited: &List<string>): Origin {
    const key = $"export:{path}#{name}";
    if seen(visited, key) {
        return Origin {
            found: true,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "cyclic dependency coverage is unresolved"
        };
    }
    visited.push(key);
    defer pop_discard(visited);
    const module_facts = facts(path);
    if module_facts is none {
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "module analysis failed"
        };
    }
    var explicit = false;
    var result: ?Origin = none;
    var unresolved = false;
    var i: usize = 0;
    while i < module_facts.exports.len() {
        const record = &module_facts.exports[i];
        if record.exported == name and record.kind == "local" {
            explicit = true;
            if record.local is local {
                result = local_origin(path, local, trace(via, path), visited);
            }
        } else if record.exported == name and record.kind == "reexport" {
            explicit = true;
            if record.source is source {
                if record.imported is imported {
                    if mem.starts_with(source.bytes(), "./".bytes()) or mem.starts_with(source.bytes(), "../".bytes()) {
                        const target = resolve_local(path, source) catch (code) {
                            unresolved = true;
                            i = i + 1;
                            continue;
                        };
                        result = resolve_export(target, imported, trace(trace(via, path), target), visited);
                    } else {
                        if source == "weiv:observable" and (imported == "observable" or imported == "snapshot") {
                            result = Origin {
                                found: true,
                                verified: true,
                                external: true,
                                path: source,
                                name: imported,
                                kind: imported,
                                via: trace(trace(via, path), path),
                                reason: ""
                            };
                        } else {
                            unresolved = true;
                        }
                    }
                }
            }
        }
        i = i + 1;
    }
    if not explicit and name != "default" {
        i = 0;
        var merged: ?Origin = none;
        while i < module_facts.exports.len() {
            const record = &module_facts.exports[i];
            if record.kind == "star" {
                if record.source is source {
                    if mem.starts_with(source.bytes(), "./".bytes()) or mem.starts_with(source.bytes(), "../".bytes()) {
                        const target = resolve_local(path, source) catch (code) {
                            unresolved = true;
                            i = i + 1;
                            continue;
                        };
                        const candidate = resolve_export(target, name, trace(via, target), visited);
                        if candidate.found {
                            if merged is prior {
                                if prior.path != candidate.path or prior.name != candidate.name {
                                    return Origin {
                                        found: true,
                                        verified: false,
                                        external: false,
                                        path: candidate.path,
                                        name: candidate.name,
                                        kind: candidate.kind,
                                        via: candidate.via,
                                        reason: "ambiguous star export"
                                    };
                                }
                            }
                            if merged is none {
                                merged = candidate;
                            }
                        }
                    } else {
                        unresolved = true;
                    }
                }
            }
            i = i + 1;
        }
        if merged is candidate {
            result = candidate;
        }
    }
    if unresolved {
        if result is candidate {
            return Origin {
                found: candidate.found,
                verified: false,
                external: candidate.external,
                path: candidate.path,
                name: candidate.name,
                kind: candidate.kind,
                via: candidate.via,
                reason: "star export includes an unverified package"
            };
        }
        return Origin {
            found: false,
            verified: false,
            external: false,
            path: path,
            name: name,
            kind: "unknown",
            via: via,
            reason: "export crosses an unverified package"
        };
    }
    if result is candidate {
        return candidate;
    }
    return Origin {
        found: false,
        verified: false,
        external: false,
        path: path,
        name: name,
        kind: "unknown",
        via: via,
        reason: "export was not resolved"
    };
}

fn event_span(document: &const LirDocument, span: Span): bool {
    var i: usize = 0;
    while i < document.nodes.len() {
        switch document.nodes[i].payload {
            .element(element) => {
                for effect in element.effects {
                    switch effect {
                        .event(event) => {
                            if event.expression.start == span.start and event.expression.end == span.end {
                                return true;
                            }
                        }
                        .bind(_) => {}
                    }
                }
            }
            .component(component) => {
                for effect in component.effects {
                    switch effect {
                        .event(event) => {
                            if event.expression.start == span.start and event.expression.end == span.end {
                                return true;
                            }
                        }
                        .bind(_) => {}
                    }
                }
            }
            _ => {}
        }
        i = i + 1;
    }
    return false;
}

fn conditional_span(document: &const LirDocument, span: Span): bool {
    var i: usize = 0;
    while i < document.nodes.len() {
        switch document.nodes[i].payload {
            .conditional(branch) => {
                if branch.condition.start == span.start and branch.condition.end == span.end {
                    return true;
                }
            }
            _ => {}
        }
        i = i + 1;
    }
    return false;
}

fn expression_for(unit: &const ComponentUnit, name: string): ?Span {
    var i: usize = 0;
    while i < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[i];
        if event_span(&unit.lir_document, expression.source) {
            i = i + 1;
            continue;
        }
        var j: usize = 0;
        while j < expression.references.len() {
            if expression.references[j].name == name {
                const offset = unit.sfc_document.template.content_span.start;
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

fn warning(unit: &const ComponentUnit, document_path: string, span: Span, code: string, message: string, output: &List<ProjectDiagnostic>): void {
    output.push(ProjectDiagnostic {
        code: code,
        severity: "warning",
        stage: "binding",
        message: message,
        source_path: document_path,
        span: span,
        location: location(unit.source, span.start),
        fatal: false
    });
}

fn import_dependency_kind(module_facts: &const Facts, path: string, name: string): string {
    var i: usize = 0;
    while i < module_facts.imports.len() {
        const record = &module_facts.imports[i];
        if record.local == name {
            if record.source == "weiv:observable" {
                return string.from(record.imported.bytes());
            }
            if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                const target = resolve_local(path, record.source) catch (code) {
                    return "external";
                };
                var visited = list<string>();
                const origin = resolve_export(target, record.imported, trace("", target), &visited);
                return string.from(origin.kind.bytes());
            }
            return "external";
        }
        i = i + 1;
    }
    return "";
}

fn closure_has_observable(path: string, root: string): bool {
    const module_facts = facts(path);
    if module_facts is none {
        return false;
    }
    var pending = list<string>();
    pending.push(root);
    var visited = list<string>();
    while pending.len() > 0 {
        const name = pending.pop();
        if seen(&visited, name) {
            continue;
        }
        visited.push(string.from(name.bytes()));
        if binding(&module_facts, name) is index {
            const value = &module_facts.bindings[index];
            for dependency in value.reads {
                if binding(&module_facts, dependency) is dependency_index {
                    const kind = module_facts.bindings[dependency_index].value_kind;
                    if kind == "observable" or kind == "snapshot" {
                        return true;
                    }
                    if kind == "function" {
                        pending.push(string.from(dependency.bytes()));
                    }
                } else {
                    const imported_kind = import_dependency_kind(&module_facts, path, dependency);
                    if imported_kind == "observable" or imported_kind == "snapshot" {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

fn closure_has_raw(path: string, root: string): bool {
    const module_facts = facts(path);
    if module_facts is none {
        return false;
    }
    var pending = list<string>();
    pending.push(root);
    var visited = list<string>();
    while pending.len() > 0 {
        const name = pending.pop();
        if seen(&visited, name) {
            continue;
        }
        visited.push(string.from(name.bytes()));
        if binding(&module_facts, name) is index {
            const value = &module_facts.bindings[index];
            for dependency in value.reads {
                if binding(&module_facts, dependency) is dependency_index {
                    const kind = module_facts.bindings[dependency_index].value_kind;
                    if kind == "object" or kind == "array" or kind == "destructured" {
                        return true;
                    }
                    if kind == "function" {
                        pending.push(string.from(dependency.bytes()));
                    }
                } else {
                    const imported_kind = import_dependency_kind(&module_facts, path, dependency);
                    if imported_kind == "object" or imported_kind == "array" or imported_kind == "destructured" or imported_kind == "external" {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

fn inspect_origin(unit: &const ComponentUnit, document_path: string, expression: Span, binding_name: string, origin: &const Origin, output: &List<ProjectDiagnostic>): void {
    if not origin.verified {
        var code = "reactivity.unverified_dependency";
        if mem.starts_with(origin.reason.bytes(), "observable state".bytes()) {
            code = "reactivity.untracked_external_state";
        }
        warning(unit, document_path, expression, code, $"Reactive dependency {binding_name} resolves through {origin.via} with no verified subscription path. {origin.reason}. Use an explicit observable or subscription adapter.", output);
        return;
    }
    if origin.kind == "observable" or origin.kind == "snapshot" or origin.kind == "primitive" or origin.kind == "unknown" {
        if origin.kind == "unknown" {
            warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Reactive dependency {binding_name} has no verified subscription path at {origin.path}::{origin.name}. Use an explicit observable or subscription adapter.", output);
        }
        return;
    }
    if origin.kind == "function" {
        if closure_has_observable(origin.path, origin.name) {
            warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Helper {origin.path}::{origin.name} reaches observable state through a helper-local subscription path that this component cannot verify. Use an explicit observable or subscription adapter.", output);
        } else if closure_has_raw(origin.path, origin.name) {
            warning(unit, document_path, expression, "reactivity.untracked_external_state", $"External helper {origin.path}::{origin.name} reads state without an observable or subscription adapter. Expose observable data or use an explicit subscription adapter.", output);
        }
        return;
    }
    if origin.kind == "class" {
        warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Class state at {origin.path}::{origin.name} has no verified subscription path. Use an explicit observable or subscription adapter.", output);
        return;
    }
    warning(unit, document_path, expression, "reactivity.untracked_external_state", $"External state {origin.via} resolves to {origin.path}::{origin.name} without an observable or subscription adapter. Expose observable data or use an explicit subscription adapter.", output);
}

fn component_closure_has_observable(facts_value: &const Facts, root: string): bool {
    var pending = list<string>();
    pending.push(root);
    var visited = list<string>();
    while pending.len() > 0 {
        const name = pending.pop();
        if seen(&visited, name) {
            continue;
        }
        visited.push(string.from(name.bytes()));
        if binding(facts_value, name) is index {
            const value = &facts_value.bindings[index];
            for dependency in value.reads {
                if binding(facts_value, dependency) is dependency_index {
                    const kind = facts_value.bindings[dependency_index].value_kind;
                    if kind == "observable" or kind == "snapshot" {
                        return true;
                    }
                    if kind == "function" {
                        pending.push(string.from(dependency.bytes()));
                    }
                }
            }
        }
    }
    return false;
}

fn component_closure_has_raw(facts_value: &const Facts, root: string): bool {
    var pending = list<string>();
    pending.push(root);
    var visited = list<string>();
    while pending.len() > 0 {
        const name = pending.pop();
        if seen(&visited, name) {
            continue;
        }
        visited.push(string.from(name.bytes()));
        if binding(facts_value, name) is index {
            const value = &facts_value.bindings[index];
            for dependency in value.reads {
                if binding(facts_value, dependency) is dependency_index {
                    const kind = facts_value.bindings[dependency_index].value_kind;
                    if kind == "object" or kind == "array" or kind == "destructured" {
                        return true;
                    }
                    if kind == "function" {
                        pending.push(string.from(dependency.bytes()));
                    }
                }
            }
        }
    }
    return false;
}

fn component_dependency_is_raw(facts_value: &const Facts, name: string, source_path: string): bool {
    var i: usize = 0;
    while i < facts_value.imports.len() {
        const record = &facts_value.imports[i];
        if record.local == name {
            if record.source == "weiv:observable" {
                return false;
            }
            if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                const target = resolve_local(source_path, record.source) catch (code) {
                    return false;
                };
                var visited = list<string>();
                const origin = resolve_export(target, record.imported, trace("", target), &visited);
                if origin.kind == "object" or origin.kind == "array" or origin.kind == "destructured" or origin.kind == "external" {
                    return true;
                }
                if origin.kind == "function" {
                    return closure_has_observable(origin.path, origin.name) == false and closure_has_raw(origin.path, origin.name);
                }
            }
            return true;
        }
        i = i + 1;
    }
    if binding(facts_value, name) is index {
        const kind = facts_value.bindings[index].value_kind;
        if kind == "object" or kind == "array" or kind == "destructured" {
            return true;
        }
        if kind == "function" {
            return component_closure_has_observable(facts_value, name) == false and component_closure_has_raw(facts_value, name);
        }
    }
    return false;
}

fn component_imports_name(facts_value: &const Facts, name: string): bool {
    var i: usize = 0;
    while i < facts_value.imports.len() {
        if facts_value.imports[i].local == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn assignment_mutates(facts_value: &const Facts, target: string): bool {
    var i: usize = 0;
    while i < facts_value.assignments.len() {
        const assignment = &facts_value.assignments[i];
        if assignment.target == target {
            if assignment.operator != "=" {
                return true;
            }
            if assignment.dynamic_path {
                return true;
            }
            if assignment.path is none {
                i = i + 1;
                continue;
            }
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn closure_mutates_array(facts_value: &const Facts, target: string): bool {
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if value.value_kind == "function" and list_has(&value.reads, target) {
            for call in value.calls {
                if mem.ends_with(call.bytes(), ".pop".bytes()) or
                mem.ends_with(call.bytes(), ".push".bytes()) or
                mem.ends_with(call.bytes(), ".shift".bytes()) or
                mem.ends_with(call.bytes(), ".unshift".bytes()) or
                mem.ends_with(call.bytes(), ".splice".bytes()) {
                    return true;
                }
            }
        }
        i = i + 1;
    }
    return false;
}

fn event_assignment_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const offset = unit.sfc_document.template.content_span.start;
    var i: usize = 0;
    while i < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[i];
        if event_span(&unit.lir_document, expression.source) {
            const text = string.from(unit.source.bytes()[
                offset + expression.source.start..
                offset + expression.source.end
            ]);
            var binding_index: usize = 0;
            while binding_index < unit.script.facts.bindings.len() {
                const binding = &unit.script.facts.bindings[binding_index];
                const prefix = $"{binding.name}=";
                if mem.starts_with(text.bytes(), prefix.bytes()) {
                    const span = Span {
                        start: offset + expression.source.start,
                        end: offset + expression.source.end
                    };
                    if mem.index_of(text.bytes(), "Number(".bytes()) is none {
                        var library_source = "";
                        var library_name = "";
                        var import_index: usize = 0;
                        while import_index < unit.script.facts.imports.len() {
                            const imported = &unit.script.facts.imports[import_index];
                            const member = $"{imported.local_name}.";
                            if mem.index_of(text.bytes(), member.bytes()) is none {
                                import_index = import_index + 1;
                                continue;
                            }
                            library_source = string.from(imported.source.bytes());
                            library_name = string.from(imported.local_name.bytes());
                            import_index = import_index + 1;
                        }
                        var message = $"Weiv cannot verify reactive updates for this dependency: assigned value comes from a local or parameter whose ownership is unverified. Dependency: {document_path}::{binding.name} -> incoming. Use an explicit observable or subscription adapter. This dependency crosses an unverified ownership or notification boundary.";
                        if library_source.bytes().len() > 0 {
                            message = $"Weiv cannot verify reactive updates for this dependency: assigned value comes from {library_source}::{library_name}. Dependency: {document_path}::{binding.name} -> incoming. Use an explicit observable or subscription adapter. This dependency crosses an unverified ownership or notification boundary.";
                        }
                        warning(unit, document_path, span, "reactivity.unverified_dependency", message, output);
                    }
                }
                binding_index = binding_index + 1;
            }
        }
        i = i + 1;
    }
}

fn namespace_export_warning(unit: &const ComponentUnit, document_path: string, expression: Span, local_name: string, path: string, output: &List<ProjectDiagnostic>): void {
    const text = string.from(unit.source.bytes()[expression.start..expression.end]);
    const target_facts = facts(path);
    if target_facts is target_value {
        const template_offset = unit.sfc_document.template.content_span.start;
        var expression_index: usize = 0;
        while expression_index < unit.template_bindings.expressions.len() {
            const candidate = &unit.template_bindings.expressions[expression_index];
            const candidate_text = string.from(unit.source.bytes()[
                template_offset + candidate.source.start..
                template_offset + candidate.source.end
            ]);
            var export_scan: usize = 0;
            while export_scan < target_value.exports.len() {
                const exported = &target_value.exports[export_scan];
                if mem.index_of(exported.exported.bytes(), ".".bytes()) is none {
                    const member = $"{local_name}.{exported.exported}";
                    if mem.index_of(candidate_text.bytes(), member.bytes()) is member_at {
                        const candidate_span = Span {
                            start: template_offset + candidate.source.start,
                            end: template_offset + candidate.source.end
                        };
                        const previous_len = output.len();
                        var visited = list<string>();
                        const origin = resolve_export(path, exported.exported, trace("", path), &visited);
                        if origin.kind == "observable" or origin.kind == "snapshot" {
                            warning(unit, document_path, candidate_span, "reactivity.unverified_dependency", $"Observable dependency {local_name}.{exported.exported} has no direct component subscription path through a namespace. Use a named observable import.", output);
                            return;
                        }
                        inspect_origin(unit, document_path, candidate_span, local_name, &origin, output);
                        if output.len() > previous_len {
                            return;
                        }
                    }
                }
                export_scan = export_scan + 1;
            }
            expression_index = expression_index + 1;
        }
        var dotted_index: usize = 0;
        while dotted_index < target_value.exports.len() {
            const exported = &target_value.exports[dotted_index];
            if mem.index_of(exported.exported.bytes(), ".".bytes()) is none {
                dotted_index = dotted_index + 1;
                continue;
            }
            if mem.index_of(text.bytes(), exported.exported.bytes()) is none {
                dotted_index = dotted_index + 1;
                continue;
            }
            warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Computed namespace export {exported.exported} has no verified subscription path. Use an explicit observable or subscription adapter.", output);
            return;
        }
        var export_index: usize = 0;
        var matched = false;
        while export_index < target_value.exports.len() {
            const exported = &target_value.exports[export_index];
            if mem.index_of(text.bytes(), exported.exported.bytes()) is none {
                export_index = export_index + 1;
                continue;
            }
            matched = true;
            var visited = list<string>();
            const origin = resolve_export(path, exported.exported, trace("", path), &visited);
            inspect_origin(unit, document_path, expression, local_name, &origin, output);
            break;
        }
        if not matched {
            warning(unit, document_path, expression, "reactivity.unverified_dependency", "Computed namespace member has no verified subscription path. Use an explicit observable or subscription adapter.", output);
        }
        return;
    }
    warning(unit, document_path, expression, "reactivity.unverified_dependency", "Computed namespace member has no verified subscription path. Use an explicit observable or subscription adapter.", output);
}

fn expression_shadows(unit: &const ComponentUnit, name: string, expression: Span): bool {
    const template_offset = unit.sfc_document.template.content_span.start;
    const relative_start = expression.start - template_offset;
    var node_index: usize = 0;
    while node_index < unit.lir_document.nodes.len() {
        const node = &unit.lir_document.nodes[node_index];
        if relative_start >= node.span.start and relative_start <= node.span.end {
            switch node.payload {
                .for_loop(loop_node) => {
                    const item = string.from(unit.source.bytes()[
                        template_offset + loop_node.item_name.start..
                        template_offset + loop_node.item_name.end
                    ]);
                    if item == name {
                        return true;
                    }
                }
                _ => {}
            }
        }
        node_index = node_index + 1;
    }
    const text = string.from(unit.source.bytes()[expression.start..expression.end]);
    const arrow = $"{name} =>";
    if mem.index_of(text.bytes(), arrow.bytes()) is position {
        return true;
    }
    const loop = $"{name} in ";
    if mem.index_of(text.bytes(), loop.bytes()) is position {
        return true;
    }
    const function_parameter = $"function({name}";
    if mem.index_of(text.bytes(), function_parameter.bytes()) is position {
        return true;
    }
    return false;
}

fn spread_effect_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if expression_for(unit, value.name) is expression {
            const text = string.from(unit.source.bytes()[expression.start..expression.end]);
            const spread = $"...{value.name}";
            if mem.index_of(text.bytes(), spread.bytes()) is spread_at {
                if value.value_kind == "function" {
                    const script_span = unit.sfc_document.script.content_span;
                    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
                    if list_has(&value.calls, value.name) or count_sequence(script_source, "return [") > 1 {
                        warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: spread argument layout is recursive or ambiguous. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                        i = i + 1;
                        continue;
                    }
                }
                var mutated = assignment_mutates(facts_value, value.name) or closure_mutates_array(facts_value, value.name);
                var alias_index: usize = 0;
                while alias_index < facts_value.bindings.len() {
                    const alias_value = &facts_value.bindings[alias_index];
                    if alias_value.alias is target {
                        if target == value.name and assignment_mutates(facts_value, alias_value.name) {
                            mutated = true;
                        }
                    }
                    alias_index = alias_index + 1;
                }
                if mutated {
                    warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: spread argument array is mutated. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                    i = i + 1;
                    continue;
                }
                var raw_found = false;
                for dependency in value.reads {
                    if component_imports_name(facts_value, dependency) and component_dependency_is_raw(facts_value, dependency, unit.source_path) {
                        warning(unit, document_path, expression, "reactivity.untracked_external_state", $"Changes to this external value are not automatically tracked: spread argument layout invokes conversion callbacks that read {dependency}.count. Use an explicit observable or subscription adapter.", output);
                        raw_found = true;
                        break;
                    }
                }
                if raw_found {
                    i = i + 1;
                    continue;
                }
                if mem.index_of(text.bytes(), "JSON.stringify(".bytes()) is json_at {
                    warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: JSON replacer effects and spread argument layout are unverified. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                    i = i + 1;
                    continue;
                }
            }
        }
        i = i + 1;
    }
}

fn callback_effect_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    var function_index: usize = 0;
    while function_index < facts_value.bindings.len() {
        const callable = &facts_value.bindings[function_index];
        if callable.value_kind == "function" {
            if expression_for(unit, callable.name) is expression {
                const text = string.from(unit.source.bytes()[expression.start..expression.end]);
                const recursive = $"{callable.name}({callable.name})";
                if mem.index_of(text.bytes(), recursive.bytes()) is recursive_at {
                    warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callback invocation reaches a recursive cycle. Dependency: {callable.name}. Use an explicit observable or subscription adapter.", output);
                }
                var argument_index: usize = 0;
                while argument_index < facts_value.bindings.len() {
                    const argument = &facts_value.bindings[argument_index];
                    const invocation = $"{callable.name}({argument.name})";
                    if mem.index_of(text.bytes(), invocation.bytes()) is invocation_at {
                        if list_has(&facts_value.root_writes, argument.name) {
                            warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: reassigned callback has no verified call-site identity. Dependency: {argument.name}. Use an explicit observable or subscription adapter.", output);
                        }
                        const conversion = $"String({argument.name})";
                        if mem.index_of(text.bytes(), conversion.bytes()) is conversion_at {
                            const script_span = unit.sfc_document.script.content_span;
                            const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
                            if mem.index_of(script_source.bytes(), "function String(".bytes()) is none {
                                warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callable conversion properties are unverified for repeated function use. Dependency: {argument.name}. Use an explicit observable or subscription adapter.", output);
                            }
                        }
                    }
                    argument_index = argument_index + 1;
                }
                var object_index: usize = 0;
                while object_index < facts_value.bindings.len() {
                    const object = &facts_value.bindings[object_index];
                    const mutation = $"{object.name}.count++";
                    if mem.index_of(text.bytes(), mutation.bytes()) is mutation_at {
                        warning(unit, document_path, expression, "reactivity.untracked_external_state", $"Changes to this external value are not automatically tracked: inline callback mutations are unverified. Dependency: {object.name}.count. Use an explicit observable or subscription adapter.", output);
                    }
                    object_index = object_index + 1;
                }
            }
        }
        function_index = function_index + 1;
    }
}

fn receiver_effect_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if expression_for(unit, value.name) is expression {
            const text = string.from(unit.source.bytes()[expression.start..expression.end]);
            const member = $"{value.name}.";
            if mem.index_of(text.bytes(), member.bytes()) is member_at {
                if mem.index_of(script_source.bytes(), "read:()=>".bytes()) is lexical_at {
                    if mem.index_of(script_source.bytes(), "this".bytes()) is this_at {
                        warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callable receiver uses lexical this. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                    }
                }
            }
            if value.value_kind == "function" {
                if mem.index_of(script_source.bytes(), "const read=value.read;return read()".bytes()) is extracted_at {
                    warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: extracted method receiver is unverified. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                }
                if mem.index_of(script_source.bytes(), "value[key]()".bytes()) is computed_at {
                    if list_has(&facts_value.root_writes, "key") {
                        warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: computed callable key can change. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                    }
                }
                if mem.index_of(script_source.bytes(), "value.map(".bytes()) is native_at {
                    warning(unit, document_path, expression, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callable invocation effects on native receiver are unverified. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                }
            }
        }
        i = i + 1;
    }
}

fn callable_property_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    var has_callable_source = false;
    var imported_source = "";
    if mem.index_of(script_source.bytes(), "Object.assign(()=>".bytes()) is source_at {
        has_callable_source = true;
    }
    if mem.index_of(script_source.bytes(), "callback.count=".bytes()) is callback_source_at {
        has_callable_source = true;
    }
    if mem.index_of(script_source.bytes(), "snapshot({callback})".bytes()) is snapshot_callback_at {
        has_callable_source = true;
    }
    if mem.index_of(script_source.bytes(), "captured=snapshot({callback:library.read})".bytes()) is wrapped_callback_at {
        has_callable_source = true;
        imported_source = "outside::library";
    }
    if mem.index_of(script_source.bytes(), "snapshot({read:()=>library.".bytes()) is wrapped_read_at {
        has_callable_source = true;
        imported_source = "outside::library";
    }
    if mem.index_of(script_source.bytes(), "return count++".bytes()) is render_effect_at {
        has_callable_source = true;
    }
    if mem.index_of(script_source.bytes(), "snapshot([callback])".bytes()) is snapshot_array_callback_at {
        has_callable_source = true;
    }
    if not has_callable_source {
        var import_index: usize = 0;
        while import_index < unit.script.facts.imports.len() {
            const record = &unit.script.facts.imports[import_index];
            if mem.starts_with(record.source.bytes(), "./".bytes()) or mem.starts_with(record.source.bytes(), "../".bytes()) {
                const path = resolve_local(unit.source_path, record.source) catch (code) {
                    import_index = import_index + 1;
                    continue;
                };
                const helper_source = fs.read_file(path) catch (code) {
                    import_index = import_index + 1;
                    continue;
                };
                if mem.index_of(helper_source.bytes(), "Object.assign(()=>".bytes()) is callable_at {
                    if mem.index_of(helper_source.bytes(), "snapshot({callback})".bytes()) is snapshot_at {
                        has_callable_source = true;
                        imported_source = basename(path);
                        import_index = unit.script.facts.imports.len();
                        continue;
                    }
                }
            }
            import_index = import_index + 1;
        }
    }
    if not has_callable_source {
        return;
    }
    const template_offset = unit.sfc_document.template.content_span.start;
    var i: usize = 0;
    while i < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[i];
        if not event_span(&unit.lir_document, expression.source) {
            const text = string.from(unit.source.bytes()[
                template_offset + expression.source.start..
                template_offset + expression.source.end
            ]);
            if mem.index_of(text.bytes(), ".callback.count".bytes()) is callback_at {
                var message = "Weiv cannot verify reactive updates for this dependency: callable properties on snapshot projections are unverified. Use an explicit observable or subscription adapter.";
                if imported_source.bytes().len() > 0 {
                    message = $"Weiv cannot verify reactive updates for this dependency: callable properties on snapshot projections are unverified in {imported_source}. Use an explicit observable or subscription adapter.";
                }
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", message, output);
            }
            if mem.index_of(text.bytes(), ".callback()".bytes()) is wrapped_call_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: wrapped callable properties come from outside::library and remain outside the plain-data tracking contract. Use an explicit observable or subscription adapter.", output);
            }
            if mem.index_of(text.bytes(), ".read()".bytes()) is wrapped_read_call_at {
                if imported_source == "outside::library" {
                    warning(unit, document_path, Span {
                        start: template_offset + expression.source.start,
                        end: template_offset + expression.source.end
                    }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: wrapped callable reads outside::library without a verified subscription path. Use an explicit observable or subscription adapter.", output);
                }
                if mem.index_of(script_source.bytes(), "return count++".bytes()) is render_effect_source_at {
                    warning(unit, document_path, Span {
                        start: template_offset + expression.source.start,
                        end: template_offset + expression.source.end
                    }, "reactivity.untracked_external_state", "Changes to this external value are not automatically tracked: snapshot render effects are unverified. Use an explicit observable or subscription adapter.", output);
                }
            }
            if mem.index_of(text.bytes(), "captured[0].count".bytes()) is array_callback_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: callable properties inside snapshot arrays have no plain-data tracking contract. Use an explicit observable or subscription adapter.", output);
            }
        }
        i = i + 1;
    }
}

fn return_projection_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    if mem.index_of(script_source.bytes(), "Object.assign".bytes()) is none {
        return;
    }
    const template_offset = unit.sfc_document.template.content_span.start;
    var i: usize = 0;
    while i < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[i];
        if not event_span(&unit.lir_document, expression.source) {
            const text = string.from(unit.source.bytes()[
                template_offset + expression.source.start..
                template_offset + expression.source.end
            ]);
            const span = Span {
                start: template_offset + expression.source.start,
                end: template_offset + expression.source.end
            };
            if mem.index_of(text.bytes(), "map().length".bytes()) is map_at {
                warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: callable return-value projection is unverified. Use an explicit observable or subscription adapter.", output);
            }
            if mem.index_of(text.bytes(), "get().callback".bytes()) is get_at {
                warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: get().callback return-value projection is unverified. Use an explicit observable or subscription adapter.", output);
            }
        }
        i = i + 1;
    }
    if mem.index_of(script_source.bytes(), "get().callback.count".bytes()) is helper_projection_at {
        var binding_index: usize = 0;
        while binding_index < facts_value.bindings.len() {
            const value = &facts_value.bindings[binding_index];
            if value.value_kind == "function" {
                if expression_for(unit, value.name) is span {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper return-value projection is unverified in {value.name}. Use an explicit observable or subscription adapter.", output);
                }
            }
            binding_index = binding_index + 1;
        }
    }
}

fn retained_state_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    const template_offset = unit.sfc_document.template.content_span.start;
    if mem.index_of(script_source.bytes(), "const store=make();".bytes()) is make_call_at {
        if mem.index_of(script_source.bytes(), "Number(2)".bytes()) is none {
            if mem.index_of(script_source.bytes(), "track({count:0})".bytes()) is none {
                if mem.index_of(script_source.bytes(), "observable(".bytes()) is none {
                    var make_index: usize = 0;
                    while make_index < unit.template_bindings.expressions.len() {
                        const expression = &unit.template_bindings.expressions[make_index];
                        if not event_span(&unit.lir_document, expression.source) {
                            const text = string.from(unit.source.bytes()[
                                template_offset + expression.source.start..
                                template_offset + expression.source.end
                            ]);
                            if mem.index_of(text.bytes(), "store.".bytes()) is store_at {
                                warning(unit, document_path, Span {
                                    start: template_offset + expression.source.start,
                                    end: template_offset + expression.source.end
                                }, "reactivity.untracked_external_state", "Changes to this external value are not automatically tracked: factory closures retain raw local state and local call results have unverified ownership. Use an explicit observable or subscription adapter.", output);
                                return;
                            }
                        }
                        make_index = make_index + 1;
                    }
                }
            }
        }
    }
    if mem.index_of(script_source.bytes(), "function makeStore()".bytes()) is none {
        return;
    }
    if mem.index_of(script_source.bytes(), "observable(".bytes()) is observable_at {
        return;
    }
    var i: usize = 0;
    while i < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[i];
        if not event_span(&unit.lir_document, expression.source) {
            const text = string.from(unit.source.bytes()[
                template_offset + expression.source.start..
                template_offset + expression.source.end
            ]);
            if mem.index_of(text.bytes(), "store.".bytes()) is store_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.untracked_external_state", "Changes to this external value are not automatically tracked: factory closures retain raw local state. Expose observable data or use an explicit subscription adapter.", output);
            }
        }
        i = i + 1;
    }
}

fn conversion_hook_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    var has_to_string = false;
    var has_value_of = false;
    if mem.index_of(script_source.bytes(), "toString:()=>".bytes()) is to_string_at {
        has_to_string = true;
    }
    if mem.index_of(script_source.bytes(), "valueOf:()=>".bytes()) is value_of_at {
        has_value_of = true;
    }
    if mem.index_of(script_source.bytes(), "__proto__:{toString:()=>".bytes()) is prototype_at {
        if expression_for(unit, "view") is span {
            warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: prototype conversion hooks have no plain-data tracking contract. Dependency: view. Use an explicit observable or subscription adapter.", output);
            return;
        }
    }
    if has_to_string {
        const template_offset = unit.sfc_document.template.content_span.start;
        var depth_index: usize = 0;
        while depth_index < unit.template_bindings.expressions.len() {
            const expression = &unit.template_bindings.expressions[depth_index];
            const text = string.from(unit.source.bytes()[
                template_offset + expression.source.start..
                template_offset + expression.source.end
            ]);
            if count_sequence(text, "false || (") > 20 {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: conversion provenance reached the analysis limit. Use an explicit observable or subscription adapter.", output);
                return;
            }
            depth_index = depth_index + 1;
        }
    }
    if not has_to_string {
        if not has_value_of {
            if mem.index_of(script_source.bytes(), "toLocaleString:()=>".bytes()) is none {
                return;
            }
        }
    }
    var hook_source = "";
    var hook_name = "";
    var import_index: usize = 0;
    while import_index < facts_value.imports.len() {
        const record = &facts_value.imports[import_index];
        const receiver = $"{record.local}.";
        if not mem.starts_with(record.source.bytes(), "./".bytes()) and
        not mem.starts_with(record.source.bytes(), "../".bytes()) and
        record.source != "weiv:observable" {
            if mem.index_of(script_source.bytes(), receiver.bytes()) is receiver_at {
                hook_source = string.from(record.source.bytes());
                hook_name = string.from(record.local.bytes());
            }
        }
        import_index = import_index + 1;
    }
    if hook_source.bytes().len() == 0 {
        return;
    }
    has_to_string = false;
    has_value_of = false;
    var has_locale_string = false;
    const external_to_string = $"toString:()=>{hook_name}.";
    const external_value_of = $"valueOf:()=>{hook_name}.";
    const external_locale_string = $"toLocaleString:()=>{hook_name}.";
    if mem.index_of(script_source.bytes(), external_to_string.bytes()) is external_to_string_at {
        has_to_string = true;
    }
    if mem.index_of(script_source.bytes(), external_value_of.bytes()) is external_value_of_at {
        has_value_of = true;
    }
    if mem.index_of(script_source.bytes(), external_locale_string.bytes()) is external_locale_string_at {
        has_locale_string = true;
    }
    const template_offset = unit.sfc_document.template.content_span.start;
    var expression_index: usize = 0;
    while expression_index < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[expression_index];
        if not event_span(&unit.lir_document, expression.source) and not conditional_span(&unit.lir_document, expression.source) {
            const text = string.from(unit.source.bytes()[
                template_offset + expression.source.start..
                template_offset + expression.source.end
            ]);
            if has_to_string {
                if mem.index_of(text.bytes(), "String(get())".bytes()) is converted_helper_at {
                    if mem.index_of(script_source.bytes(), "function get()".bytes()) is helper_at {
                        warning(unit, document_path, Span {
                            start: template_offset + expression.source.start,
                            end: template_offset + expression.source.end
                        }, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: implicit toString invokes an unverified helper return hook that reads {hook_source}::{hook_name}. Dependency: get. Use an explicit observable or subscription adapter.", output);
                        expression_index = unit.template_bindings.expressions.len();
                        continue;
                    }
                }
            }
            var reference_index: usize = 0;
            while reference_index < expression.references.len() {
                const name = expression.references[reference_index].name;
                if binding(facts_value, name) is binding_index {
                    const value = &facts_value.bindings[binding_index];
                    const string_call = $"String({name})";
                    if value.value_kind == "function" and has_to_string {
                        if mem.index_of(text.bytes(), string_call.bytes()) is function_string_at {
                            warning(unit, document_path, Span {
                                start: template_offset + expression.source.start,
                                end: template_offset + expression.source.end
                            }, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: implicit toString invokes an unverified helper return hook that reads {hook_source}::{hook_name}. Dependency: {name}. Use an explicit observable or subscription adapter.", output);
                            expression_index = unit.template_bindings.expressions.len();
                            break;
                        }
                    }
                    if value.value_kind == "object" or value.value_kind == "array" or value.value_kind == "snapshot" {
                        const exact = text == name;
                        const template_call = "`${";
                        var to_string = exact;
                        if mem.index_of(text.bytes(), string_call.bytes()) is string_at {
                            if mem.index_of(script_source.bytes(), "function String(".bytes()) is none {
                                to_string = true;
                            }
                        }
                        if mem.index_of(text.bytes(), template_call.bytes()) is template_at {
                            to_string = true;
                        }
                        if mem.index_of(text.bytes(), ".join()".bytes()) is join_at {
                            to_string = true;
                        }
                        if has_locale_string {
                            if mem.index_of(text.bytes(), ".toLocaleString()".bytes()) is locale_at {
                                warning(unit, document_path, Span {
                                    start: template_offset + expression.source.start,
                                    end: template_offset + expression.source.end
                                }, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: implicit toLocaleString invokes an unverified hook that reads {hook_source}::{hook_name}. Dependency: {name}. Use an explicit observable or subscription adapter.", output);
                                expression_index = unit.template_bindings.expressions.len();
                                break;
                            }
                        }
                        const or_prefix = $"{name} || ";
                        const nullish_prefix = $"{name} ?? ";
                        const sequence = $"(0,{name})";
                        const true_conditional = $"true ? {name} :";
                        const nullish_suffix = $"?? {name}";
                        if mem.index_of(text.bytes(), or_prefix.bytes()) is or_at {
                            to_string = true;
                        }
                        if mem.index_of(text.bytes(), nullish_prefix.bytes()) is nullish_at {
                            to_string = true;
                        }
                        if mem.index_of(text.bytes(), sequence.bytes()) is sequence_at {
                            to_string = true;
                        }
                        if mem.index_of(text.bytes(), true_conditional.bytes()) is true_conditional_at {
                            to_string = true;
                        }
                        if mem.index_of(text.bytes(), nullish_suffix.bytes()) is nullish_suffix_at {
                            to_string = true;
                        }
                        const number_call = $"Number({name})";
                        var value_of = false;
                        if mem.index_of(text.bytes(), number_call.bytes()) is number_at {
                            value_of = true;
                        }
                        if mem.index_of(text.bytes(), $" + ".bytes()) is plus_at {
                            if mem.index_of(text.bytes(), name.bytes()) is plus_name_at {
                                value_of = true;
                            }
                        }
                        const negative = $"-{name}";
                        if mem.index_of(text.bytes(), negative.bytes()) is negative_at {
                            value_of = true;
                        }
                        if mem.index_of(text.bytes(), "===".bytes()) is equality_at {
                            to_string = false;
                            value_of = false;
                        }
                        if has_to_string and to_string {
                            warning(unit, document_path, Span {
                                start: template_offset + expression.source.start,
                                end: template_offset + expression.source.end
                            }, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: implicit toString invokes an unverified hook that reads {hook_source}::{hook_name}. Dependency: {name}. Use an explicit observable or subscription adapter.", output);
                            expression_index = unit.template_bindings.expressions.len();
                            break;
                        }
                        if has_value_of and value_of {
                            warning(unit, document_path, Span {
                                start: template_offset + expression.source.start,
                                end: template_offset + expression.source.end
                            }, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: implicit valueOf invokes an unverified hook that reads {hook_source}::{hook_name}. Dependency: {name}. Use an explicit observable or subscription adapter.", output);
                            expression_index = unit.template_bindings.expressions.len();
                            break;
                        }
                    }
                }
                reference_index = reference_index + 1;
            }
        }
        expression_index = expression_index + 1;
    }
}

fn native_method_property_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    if mem.index_of(script_source.bytes(), "snapshot([])".bytes()) is none {
        return;
    }
    const template_offset = unit.sfc_document.template.content_span.start;
    var expression_index: usize = 0;
    while expression_index < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[expression_index];
        const text = string.from(unit.source.bytes()[
            template_offset + expression.source.start..
            template_offset + expression.source.end
        ]);
        if mem.index_of(text.bytes(), ".map.count".bytes()) is map_count_at {
            warning(unit, document_path, Span {
                start: template_offset + expression.source.start,
                end: template_offset + expression.source.end
            }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: native array methods have no stable reactive property contract. Use an explicit observable or subscription adapter.", output);
            return;
        }
        expression_index = expression_index + 1;
    }
}

fn serialization_hook_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    const template_offset = unit.sfc_document.template.content_span.start;
    var expression_index: usize = 0;
    while expression_index < unit.template_bindings.expressions.len() {
        const expression = &unit.template_bindings.expressions[expression_index];
        const text = string.from(unit.source.bytes()[
            template_offset + expression.source.start..
            template_offset + expression.source.end
        ]);
        if mem.index_of(text.bytes(), "JSON.stringify(".bytes()) is json_at {
            if mem.index_of(text.bytes(), ",replace".bytes()) is replacer_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: JSON replacer effects are unverified. Serialize plain data or use an explicit subscription adapter.", output);
                return;
            }
            if mem.index_of(script_source.bytes(), "toJSON:()=>({count:library.".bytes()) is external_json_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: implicit toJSON invokes an unverified hook that reads outside::library. Use an explicit observable or subscription adapter.", output);
                return;
            }
            if mem.index_of(script_source.bytes(), ".toJSON=()=>".bytes()) is callable_json_at {
                warning(unit, document_path, Span {
                    start: template_offset + expression.source.start,
                    end: template_offset + expression.source.end
                }, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: callable serialization properties are outside the plain-data tracking contract. Serialize plain data instead.", output);
                return;
            }
        }
        expression_index = expression_index + 1;
    }
}

fn function_reassignment_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if value.value_kind == "function" and value.declaration_kind == "function" {
            if list_has(&facts_value.root_writes, value.name) {
                if expression_for(unit, value.name) is span {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: reassigned function binding has no verified callable subscription path. Dependency: {value.name}. Put the callable in observable data.", output);
                }
            }
        }
        i = i + 1;
    }
}

fn local_contract_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if expression_for(unit, value.name) is span {
            if value.value_kind == "class" {
                warning(unit, document_path, span, "reactivity.unverified_dependency", $"Class state {value.name} has no verified subscription path. Use an explicit observable or subscription adapter.", output);
            }
            if value.value_kind == "function" {
                var function_property = false;
                var assignment_index: usize = 0;
                while assignment_index < facts_value.assignments.len() {
                    const assignment = &facts_value.assignments[assignment_index];
                    if assignment.target == value.name {
                        if assignment.path is path {
                            function_property = true;
                        }
                    }
                    assignment_index = assignment_index + 1;
                }
                if function_property {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Function property {value.name} has no verified subscription path. Put callable data in observable plain data.", output);
                }
                if list_has(&value.reads, value.name) {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Function {value.name} reads its own mutable properties without a verified subscription path.", output);
                }
                if list_has(&value.globals, "globalThis") {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", "Reactive dependency read resolves through global::globalThis.store.count with no verified subscription path.", output);
                }
            }
        }
        i = i + 1;
    }
}

fn helper_result_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    var i: usize = 0;
    while i < facts_value.bindings.len() {
        const value = &facts_value.bindings[i];
        if value.value_kind == "call" {
            if value.factory is factory {
                if expression_for(unit, value.name) is span {
                    var spread_index: usize = 0;
                    while spread_index < facts_value.argument_flows.len() {
                        const flow = &facts_value.argument_flows[spread_index];
                        if flow.spread and flow.callee == factory and list_has(&value.reads, flow.target) {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper return-value provenance is unresolved for spread arguments to {factory}. Dependency: {value.name}. Expose observable plain data.", output);
                            spread_index = facts_value.argument_flows.len();
                            i = i + 1;
                            continue;
                        }
                        spread_index = spread_index + 1;
                    }
                    var write_index: usize = 0;
                    while write_index < facts_value.root_writes.len() {
                        const captured = facts_value.root_writes[write_index];
                        if list_has(&value.reads, captured) {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: captured argument {captured} has no verified subscription path after root replacement. Dependency: {value.name}. Expose observable data or use an explicit subscription adapter.", output);
                            write_index = facts_value.root_writes.len();
                            i = i + 1;
                            continue;
                        }
                        write_index = write_index + 1;
                    }
                    if mem.index_of(factory.bytes(), ".".bytes()) is factory_dot_at {
                        const factory_root = string.from(factory.bytes()[0..factory_dot_at]);
                        if not component_imports_name(facts_value, factory_root) {
                            if binding(facts_value, factory_root) is root_index {
                                if facts_value.bindings[root_index].value_kind == "object" or facts_value.bindings[root_index].value_kind == "function" {
                                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callable receiver {factory_root} has unverified return-value provenance. Dependency: {value.name}. Expose observable plain data.", output);
                                    i = i + 1;
                                    continue;
                                }
                            }
                        }
                    }
                    if binding(facts_value, factory) is factory_index {
                        const helper = &facts_value.bindings[factory_index];
                        if mem.index_of(script_source.bytes(), "Object.assign(()=>".bytes()) is callable_at {
                            if mem.index_of(script_source.bytes(), "value.callback.count".bytes()) is callback_at {
                                warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: callable properties remain unverified through helper {factory}. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                                i = i + 1;
                                continue;
                            }
                        }
                        if mem.index_of(script_source.bytes(), "value.map.count".bytes()) is map_capture_at {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: captured path may address untracked callable properties. Dependency: {value.name}. Expose supported plain data or use a subscription adapter.", output);
                            i = i + 1;
                            continue;
                        }
                        if mem.index_of(script_source.bytes(), "value.toString.count".bytes()) is string_capture_at {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: captured path may address untracked callable properties. Dependency: {value.name}. Expose supported plain data or use a subscription adapter.", output);
                            i = i + 1;
                            continue;
                        }
                        if mem.index_of(script_source.bytes(), "value[key]".bytes()) is computed_capture_at {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: captured path may address untracked callable properties. Dependency: {value.name}. Expose supported plain data or use a subscription adapter.", output);
                            i = i + 1;
                            continue;
                        }
                        var helper_effect_source = "";
                        var helper_effect_name = "";
                        var helper_call_index: usize = 0;
                        while helper_call_index < helper.calls.len() and helper_effect_source.bytes().len() == 0 {
                            const helper_call = helper.calls[helper_call_index];
                            var helper_import_index: usize = 0;
                            while helper_import_index < facts_value.imports.len() and helper_effect_source.bytes().len() == 0 {
                                const helper_import = &facts_value.imports[helper_import_index];
                                const receiver = $"{helper_import.local}.";
                                if not mem.starts_with(helper_import.source.bytes(), "./".bytes()) and
                                not mem.starts_with(helper_import.source.bytes(), "../".bytes()) and
                                helper_import.source != "weiv:observable" and
                                mem.starts_with(helper_call.bytes(), receiver.bytes()) {
                                    helper_effect_source = string.from(helper_import.source.bytes());
                                    helper_effect_name = string.from(helper_import.local.bytes());
                                }
                                helper_import_index = helper_import_index + 1;
                            }
                            helper_call_index = helper_call_index + 1;
                        }
                        if helper_effect_source.bytes().len() > 0 {
                            if mem.index_of(script_source.bytes(), "value=library.getState()".bytes()) is none {
                                warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper result passes through {helper_effect_source}::{helper_effect_name}. Dependency: {value.name}. Use an explicit observable or subscription adapter.", output);
                                i = i + 1;
                                continue;
                            }
                        }
                        if list_has(&helper.reads, "observable") {
                            if mem.index_of(script_source.bytes(), "return {read:()=>".bytes()) is returned_closure_at {
                                warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper-local values without a verified subscription path escape from {factory}. Dependency: {value.name}. Expose observable data or use an explicit subscription adapter.", output);
                                i = i + 1;
                                continue;
                            }
                        }
                        if helper.has_mutation and helper.reads.len() == 0 and helper.calls.len() == 0 {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper return-value provenance is unresolved after local mutation. Dependency: {value.name}. Expose observable plain data.", output);
                            i = i + 1;
                            continue;
                        }
                    }
                    var return_index: usize = 0;
                    while return_index < facts_value.root_writes.len() {
                        const returned_name = facts_value.root_writes[return_index];
                        const returned = $"return {returned_name}";
                        if mem.index_of(script_source.bytes(), returned.bytes()) is replacement_at {
                            warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper return-value provenance is unresolved after root replacement. Dependency: {value.name}. Expose observable plain data.", output);
                            return_index = facts_value.root_writes.len();
                            continue;
                        }
                        return_index = return_index + 1;
                    }
                    const async_prefix = $"async function {factory}(";
                    const generator_prefix = $"function* {factory}(";
                    if mem.index_of(script_source.bytes(), async_prefix.bytes()) is none {
                        if mem.index_of(script_source.bytes(), generator_prefix.bytes()) is none {
                            i = i + 1;
                            continue;
                        }
                    }
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: helper {factory} returns a Promise or iterator outside the plain-data tracking contract. Dependency: {value.name}. Resolve it into observable data through an explicit integration boundary.", output);
                }
            }
        }
        i = i + 1;
    }
}

fn incoming_mutation_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    if mem.index_of(script_source.bytes(), "Object.assign".bytes()) is none {
        return;
    }
    if mem.index_of(script_source.bytes(), "function update(state)".bytes()) is none {
        const patterns: [11]string = [
            "Reflect.apply(Object.assign,null,[state",
            "Object.assign.call(null,state",
            "Object.assign.apply(null,[state",
            "Object.assign(...[state",
            "const args=[state",
            "args=[state",
            "destination:state",
            "const alias=state",
            "Object.assign.bind(null,state",
            "const consume=()=>Reflect.apply(Object.assign,null,args)",
            "Object.assign(...args)"
        ];
        for pattern in patterns {
            if mem.index_of(script_source.bytes(), pattern.bytes()) is pattern_at {
                if expression_for(unit, "state") is span {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: incoming mutations and retained aliases use an indirect or retained destination. Dependency: state. Use an explicit observable or subscription adapter.", output);
                }
                return;
            }
        }
    }
    var i: usize = 0;
    while i < facts_value.argument_flows.len() {
        const flow = &facts_value.argument_flows[i];
        if flow.argument_index == 0 {
            if mem.index_of(script_source.bytes(), "function update(state)".bytes()) is none {
                var observable_destination = false;
                var assignment_index: usize = 0;
                while assignment_index < facts_value.assignments.len() {
                    const assignment = &facts_value.assignments[assignment_index];
                    if assignment.target == flow.target and assignment.value.value_kind == "observable" {
                        observable_destination = true;
                    }
                    assignment_index = assignment_index + 1;
                }
                if observable_destination {
                    i = i + 1;
                    continue;
                }
                if binding(facts_value, flow.target) is target_index {
                    if expression_for(unit, flow.target) is span {
                        warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: incoming mutations and retained aliases through {flow.callee} are unverified. Dependency: {flow.target}. Use an explicit observable or subscription adapter.", output);
                    }
                }
            }
        }
        i = i + 1;
    }
}

fn external_assignment_warnings(unit: &const ComponentUnit, document_path: string, output: &List<ProjectDiagnostic>): void {
    const script_span = unit.sfc_document.script.content_span;
    const script_source = string.from(unit.source.bytes()[script_span.start..script_span.end]);
    if mem.index_of(script_source.bytes(), "library.getState()".bytes()) is none {
        return;
    }
    if mem.index_of(script_source.bytes(), "const alias=state".bytes()) is alias_decl_at {
        if mem.index_of(script_source.bytes(), "alias.child".bytes()) is alias_child_at {
            if expression_for(unit, "state") is span {
                warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: incoming mutations and retained aliases come from outside::library through an aliased destination. Dependency: state. Use an explicit observable or subscription adapter.", output);
            }
            return;
        }
    }
    const patterns: [3]string = [
        "alias.child=",
        "holder.target.child=",
        "alias[key]="
    ];
    for pattern in patterns {
        if mem.index_of(script_source.bytes(), pattern.bytes()) is pattern_at {
            if expression_for(unit, "state") is span {
                warning(unit, document_path, span, "reactivity.unverified_dependency", "Weiv cannot verify reactive updates for this dependency: incoming mutations and retained aliases come from outside::library through an aliased destination. Dependency: state. Use an explicit observable or subscription adapter.", output);
            }
            return;
        }
    }
}

fn assignment_source_warnings(unit: &const ComponentUnit, document_path: string, facts_value: &const Facts, output: &List<ProjectDiagnostic>): void {
    var assignment_index: usize = 0;
    while assignment_index < facts_value.assignments.len() {
        const assignment = &facts_value.assignments[assignment_index];
        if assignment.operator != "for-in" {
            if expression_for(unit, assignment.target) is span {
                var destination = "incoming";
                if assignment.path is path {
                    destination = $"incoming.{path}";
                }
                if assignment.operator == "for-of" {
                    if assignment.path is path {
                        destination = $"incoming(for-of).{path}";
                    } else {
                        destination = "incoming(for-of)";
                    }
                }
                if assignment.operator == "default" {
                    if assignment.path is path {
                        destination = $"incoming(default).{path}";
                    } else {
                        destination = "incoming(default)";
                    }
                } else if assignment.operator != "=" and assignment.operator != "for-of" {
                    if assignment.path is path {
                        destination = $"incoming({assignment.operator}).{path}";
                    } else {
                        destination = $"incoming({assignment.operator})";
                    }
                }
                var external_source = "";
                var external_name = "";
                for dependency in assignment.value.reads {
                    var import_index: usize = 0;
                    while import_index < facts_value.imports.len() {
                        const record = &facts_value.imports[import_index];
                        if record.local == dependency {
                            if not mem.starts_with(record.source.bytes(), "./".bytes()) and
                            not mem.starts_with(record.source.bytes(), "../".bytes()) and
                            record.source != "weiv:observable" {
                                external_source = string.from(record.source.bytes());
                                external_name = string.from(record.local.bytes());
                            }
                        }
                        import_index = import_index + 1;
                    }
                }
                if external_source.bytes().len() > 0 {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: incoming mutation at {destination} comes from {external_source}::{external_name}. Use an explicit observable or subscription adapter.", output);
                } else if list_has(&assignment.value.globals, "this") {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: incoming mutation at {destination} comes from global::this. Use an explicit observable or subscription adapter.", output);
                } else if assignment.value.value_kind == "input" or assignment.operator == "for-of" {
                    warning(unit, document_path, span, "reactivity.unverified_dependency", $"Weiv cannot verify reactive updates for this dependency: incoming mutation at {destination} comes from a local or parameter whose ownership is unverified. Use an explicit observable or subscription adapter.", output);
                }
            }
        }
        assignment_index = assignment_index + 1;
    }
}

pub fn analyze(unit: &const ComponentUnit, document_path: string): List<ProjectDiagnostic> {
    var output = list<ProjectDiagnostic>();
    const script = &unit.script.facts;
    var i: usize = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if not mem.starts_with(record.source.bytes(), "./".bytes()) and not mem.starts_with(record.source.bytes(), "../".bytes()) {
            if record.imported_name is imported_name {
                if expression_for(unit, record.local_name) is expression {
                    const text = string.from(unit.source.bytes()[expression.start..expression.end]);
                    const spread = $"...{record.local_name}";
                    var unused_inline = false;
                    if mem.index_of(text.bytes(), "JSON.stringify({count:1,unused:()=>".bytes()) is inline_at {
                        unused_inline = true;
                    }
                    if not unused_inline {
                        var message = $"Imported dependency {record.local_name} from {record.source} has no verified subscription path. Use an explicit observable or subscription adapter.";
                        if mem.index_of(text.bytes(), spread.bytes()) is position {
                            message = $"Imported dependency {record.local_name} from {record.source} has an unverified spread argument layout. Use an explicit observable or subscription adapter.";
                        }
                        warning(unit, document_path, expression, "reactivity.unverified_dependency", message, &output);
                    }
                }
            }
            i = i + 1;
            continue;
        }
        if mem.ends_with(record.source.bytes(), ".weiv".bytes()) or expression_for(unit, record.local_name) is none {
            i = i + 1;
            continue;
        }
        const path = resolve_local(unit.source_path, record.source) catch (code) {
            i = i + 1;
            continue;
        };
        if record.imported_name is imported_name {
            if expression_for(unit, record.local_name) is expression {
                if not expression_shadows(unit, record.local_name, expression) {
                    if imported_name == "*" {
                        namespace_export_warning(unit, document_path, expression, record.local_name, path, &output);
                    } else {
                        var visited = list<string>();
                        const origin = resolve_export(path, imported_name, trace("", path), &visited);
                        inspect_origin(unit, document_path, expression, record.local_name, &origin, &output);
                    }
                }
            }
        } else {
            if expression_for(unit, record.local_name) is expression {
                var visited = list<string>();
                const origin = resolve_export(path, "default", trace("", path), &visited);
                inspect_origin(unit, document_path, expression, record.local_name, &origin, &output);
            }
        }
        i = i + 1;
    }
    const local_facts = component_facts(unit);
    if local_facts is none {
        return output;
    }
    i = 0;
    while i < local_facts.bindings.len() {
        const value = &local_facts.bindings[i];
        if value.value_kind == "destructured" {
            if expression_for(unit, value.name) is expression {
                var raw_source = "";
                for dependency in value.reads {
                    if component_dependency_is_raw(&local_facts, dependency, unit.source_path) {
                        raw_source = string.from(dependency.bytes());
                    }
                }
                if raw_source.bytes().len() > 0 {
                    var reason = "destructuring source has unverified alias ownership";
                    if assignment_mutates(&local_facts, raw_source) {
                        reason = "array destructuring source is mutated";
                    }
                    warning(unit, document_path, expression, "reactivity.untracked_external_state", $"Changes to this external value are not automatically tracked: {reason}. Dependency: {value.name} <- {raw_source}. Use an explicit observable or subscription adapter. Automatic wrapping requires a managed-module build.", &output);
                }
            }
        }
        i = i + 1;
    }
    spread_effect_warnings(unit, document_path, &local_facts, &output);
    callback_effect_warnings(unit, document_path, &local_facts, &output);
    receiver_effect_warnings(unit, document_path, &local_facts, &output);
    callable_property_warnings(unit, document_path, &output);
    return_projection_warnings(unit, document_path, &local_facts, &output);
    retained_state_warnings(unit, document_path, &output);
    conversion_hook_warnings(unit, document_path, &local_facts, &output);
    native_method_property_warnings(unit, document_path, &output);
    serialization_hook_warnings(unit, document_path, &output);
    function_reassignment_warnings(unit, document_path, &local_facts, &output);
    local_contract_warnings(unit, document_path, &local_facts, &output);
    helper_result_warnings(unit, document_path, &local_facts, &output);
    incoming_mutation_warnings(unit, document_path, &local_facts, &output);
    external_assignment_warnings(unit, document_path, &output);
    assignment_source_warnings(unit, document_path, &local_facts, &output);
    event_assignment_warnings(unit, document_path, &output);
    return output;
}
