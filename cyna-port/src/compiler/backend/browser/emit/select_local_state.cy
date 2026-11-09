// Operation: browser dependency graph and script facts -> local cell selection.
import { BrowserComponent } from .compiler.backend.browser.component;
import { CellSelection, LocalSubscription, ManagedSubscription } from .compiler.backend.browser.emit.cell_selection;
import { is_props, is_imported } from .compiler.backend.browser.classify_tracked_roots;
import { analyze_module_state_raw } from .ffi.script_backend;
import std.json;
import std.mem;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;

struct LocalDependency {
    name: string;
    value_kind: string;
    reads: List<string>;
}

struct DependencyLookup {
    name: string;
    binding: string;
}

fn decode_text(value: &const Value): string ! ScriptDecodeError {
    return try validation.text(value);
}

fn decode_dependency(value: &const Value): LocalDependency ! ScriptDecodeError {
    return switch value {
        .object(object) => LocalDependency {
            name: try validation.text_field(&object, "name"),
            value_kind: try validation.text_field(&object, "value_kind"),
            reads: try validation.record_field<string>(&object, "reads", decode_text)
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn has_local_name(selection: &const CellSelection, name: string): bool {
    var i: usize = 0;
    while i < selection.local_names.len() {
        if selection.local_names[i] == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn has_local_subscription(selection: &const CellSelection, name: string, binding: string): bool {
    var i: usize = 0;
    while i < selection.local_subscriptions.len() {
        const subscription = &selection.local_subscriptions[i];
        if subscription.name == name and subscription.binding == binding {
            return true;
        }
        i = i + 1;
    }
    return false;
}

fn add_local(selection: &CellSelection, name: string, binding: string): void {
    if not has_local_name(selection, name) {
        selection.local_names.push(string.from(name.bytes()));
    }
    if not has_local_subscription(selection, name, binding) {
        selection.local_subscriptions.push(LocalSubscription {
            name: string.from(name.bytes()),
            binding: string.from(binding.bytes()),
            publisher_backed: false
        });
    }
}

fn add_dependency_subscription(selection: &CellSelection, name: string, binding: string): void {
    if not has_local_subscription(selection, name, binding) {
        selection.local_subscriptions.push(LocalSubscription {
            name: string.from(name.bytes()),
            binding: string.from(binding.bytes()),
            publisher_backed: false
        });
    }
}

fn add_dependency_closure(component: &const BrowserComponent, selection: &CellSelection): void {
    const span = component.unit.sfc_document.script.content_span;
    const source = string.from(component.unit.source.bytes()[span.start..span.end]);
    const raw = analyze_module_state_raw(source, component.unit.source_path) catch (code) {
        return;
    };
    const value = json.parse(raw) catch (code) {
        return;
    };
    var bindings = list<LocalDependency>();
    switch value {
        .object(object) => {
            bindings = validation.record_field<LocalDependency>(&object, "bindings", decode_dependency) catch (code) {
                return;
            };
        }
        _ => {
            return;
        }
    }
    var pending = list<DependencyLookup>();
    var i: usize = 0;
    while i < selection.local_subscriptions.len() {
        const subscription = &selection.local_subscriptions[i];
        pending.push(DependencyLookup {
            name: string.from(subscription.name.bytes()),
            binding: string.from(subscription.binding.bytes())
        });
        i = i + 1;
    }
    var region_index: usize = 0;
    while region_index < component.region_graph.regions.len() {
        const region = &component.region_graph.regions[region_index];
        var dependency_index: usize = 0;
        while dependency_index < region.dependency_names.len() {
            const name = region.dependency_names[dependency_index];
            var duplicate = false;
            var pending_index: usize = 0;
            while pending_index < pending.len() {
                if pending[pending_index].name == name {
                    duplicate = true;
                }
                pending_index = pending_index + 1;
            }
            if not duplicate {
                pending.push(DependencyLookup {
                    name: string.from(name.bytes()),
                    binding: string.from(name.bytes())
                });
            }
            dependency_index = dependency_index + 1;
        }
        region_index = region_index + 1;
    }
    var visited = list<string>();
    while pending.len() > 0 {
        const lookup = pending.pop();
        var seen = false;
        var j: usize = 0;
        while j < visited.len() {
            if visited[j] == lookup.name {
                seen = true;
            }
            j = j + 1;
        }
        if seen {
            continue;
        }
        visited.push(string.from(lookup.name.bytes()));
        var binding_index: ?usize = none;
        j = 0;
        while j < bindings.len() {
            if bindings[j].name == lookup.name {
                binding_index = j;
            }
            j = j + 1;
        }
        if binding_index is index {
            const binding = &bindings[index];
            for dependency in binding.reads {
                if dependency == "props" or is_props(&component.unit.script.facts, dependency) {
                    continue;
                }
                if is_imported(&component.unit.script.facts, dependency) {
                    add_dependency_subscription(selection, dependency, lookup.binding);
                    continue;
                }
                var local = false;
                j = 0;
                while j < bindings.len() {
                    if bindings[j].name == dependency and bindings[j].value_kind != "function" {
                        local = true;
                    }
                    j = j + 1;
                }
                if local {
                    add_local(selection, dependency, lookup.binding);
                    pending.push(DependencyLookup {
                        name: string.from(dependency.bytes()),
                        binding: string.from(lookup.binding.bytes())
                    });
                }
            }
        }
    }
}

fn used_by_region(component: &const BrowserComponent, name: string): bool {
    var r: usize = 0;
    while r < component.region_graph.regions.len() {
        const region = &component.region_graph.regions[r];
        var d: usize = 0;
        while d < region.dependency_names.len() {
            if region.dependency_names[d] == name {
                return true;
            }
            d = d + 1;
        }
        r = r + 1;
    }
    return false;
}

pub fn select_into(component: &const BrowserComponent, selection: &CellSelection): void {
    const script = &component.unit.script.facts;
    var i: usize = 0;
    while i < script.bindings.len() {
        const binding = &script.bindings[i];
        const imported = is_imported(script, binding.name);
        if binding.template_visible and (binding.kind == "mutable" or binding.kind == "immutable") and not imported and not is_props(script, binding.name) {
            if used_by_region(component, binding.name) {
                selection.local_names.push(string.from(binding.name.bytes()));
                selection.local_subscriptions.push({
                    name: string.from(binding.name.bytes()),
                    binding: string.from(binding.name.bytes()),
                    publisher_backed: false
                });
            }
        }
        i = i + 1;
    }
    i = 0;
    while i < script.imports.len() {
        const record = &script.imports[i];
        if record.local_name.bytes().len() > 0 and not mem.ends_with(record.source.bytes(), ".weiv".bytes()) and used_by_region(component, record.local_name) {
            selection.local_subscriptions.push({
                name: string.from(record.local_name.bytes()),
                binding: string.from(record.local_name.bytes()),
                publisher_backed: false
            });
        }
        i = i + 1;
    }
    add_dependency_closure(component, selection);
    return;
}
