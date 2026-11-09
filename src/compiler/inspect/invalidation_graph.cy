// Operation: compiled browser component -> human-readable invalidation graph.
import { BrowserComponent } from .compiler.backend.browser.component;
import { RegionKind, region_kind_label } from .compiler.backend.browser.region_graph;
import { kind_label } from .compiler.backend.browser.tracked_roots;
import { DependencyList } from .compiler.backend.browser.dependencies;
import { collect_expression } from .compiler.backend.browser.collect_dependencies;
import { collect as collect_paths } from .compiler.backend.browser.collect_tracked_paths;
import { Span } from .compiler.source;
import std.mem;

struct Diagnostic {
    severity: string;
    kind: string;
    subject: string;
    reason: ?string;
}

struct FormatState {
    next_region_id: usize;
    diagnostics: List<Diagnostic>;
}

fn append_indent(out: &List<u8>, depth: usize): void {
    var i: usize = 0;
    while i < depth {
        out.push(32);
        out.push(32);
        i = i + 1;
    }
}

fn append_list(out: &List<u8>, values: &const List<string>): void {
    var i: usize = 0;
    while i < values.len() {
        if i > 0 {
            out.push(44);
        }
        for byte in values[i].bytes() {
            out.push(byte);
        }
        i = i + 1;
    }
}

fn append_ids(out: &List<u8>, values: &const List<usize>): void {
    var i: usize = 0;
    while i < values.len() {
        if i > 0 {
            out.push(44);
        }
        const value = values[i];
        for byte in $"{value}".bytes() {
            out.push(byte);
        }
        i = i + 1;
    }
}

fn template_text(component: &const BrowserComponent, span: Span): string {
    const offset = component.unit.sfc_document.template.content_span.start;
    return string.from(component.unit.source.bytes()[offset + span.start..offset + span.end]);
}

fn template_source(component: &const BrowserComponent): []const u8 {
    const span = component.unit.sfc_document.template.content_span;
    return component.unit.source.bytes()[span.start..span.end];
}

fn script_text(component: &const BrowserComponent): string {
    const span = component.unit.sfc_document.script.content_span;
    return string.from(component.unit.source.bytes()[span.start..span.end]);
}

fn contains(text: string, needle: string): bool {
    if mem.index_of(text.bytes(), needle.bytes()) is none {
        return false;
    }
    return true;
}

fn is_ident_start(byte: u8): bool {
    return (byte >= 65 and byte <= 90) or
    (byte >= 97 and byte <= 122) or
    byte == 95 or
    byte == 36;
}

fn is_ident_continue(byte: u8): bool {
    return is_ident_start(byte) or (byte >= 48 and byte <= 57);
}

fn simple_access(text: string): bool {
    const bytes = text.bytes();
    if bytes.len() == 0 or not is_ident_start(bytes[0]) {
        return false;
    }
    var i: usize = 1;
    while i < bytes.len() {
        if bytes[i] == 46 {
            i = i + 1;
            if i >= bytes.len() or not is_ident_start(bytes[i]) {
                return false;
            }
            i = i + 1;
            while i < bytes.len() and is_ident_continue(bytes[i]) {
                i = i + 1;
            }
            continue;
        }
        if not is_ident_continue(bytes[i]) {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn literal_expression(text: string): bool {
    const bytes = text.bytes();
    if bytes.len() == 0 {
        return false;
    }
    if bytes.len() >= 2 and (bytes[0] == 39 or bytes[0] == 34) {
        return bytes[bytes.len() - 1] == bytes[0];
    }
    if text == "true" or text == "false" or text == "null" or text == "undefined" {
        return true;
    }
    var digit = false;
    var dot = false;
    var i: usize = 0;
    if bytes[0] == 43 or bytes[0] == 45 {
        i = 1;
    }
    while i < bytes.len() {
        if bytes[i] >= 48 and bytes[i] <= 57 {
            digit = true;
        } else if bytes[i] == 46 and not dot {
            dot = true;
        } else {
            return false;
        }
        i = i + 1;
    }
    return digit;
}

fn supported_punctuation(byte: u8): bool {
    return byte == 46 or byte == 40 or byte == 41 or byte == 91 or byte == 93 or
    byte == 63 or byte == 58 or byte == 33 or byte == 61 or byte == 62 or
    byte == 60 or byte == 38 or byte == 124 or byte == 43 or byte == 45 or
    byte == 42 or byte == 47 or byte == 37 or byte == 44 or byte == 32 or
    byte == 10 or byte == 13 or byte == 9 or byte == 39 or byte == 34 or
    byte == 123 or byte == 125 or byte == 59;
}

fn direct_expression(text: string): bool {
    if text.bytes().len() == 0 or literal_expression(text) or simple_access(text) {
        return true;
    }
    if contains(text, "function (") or contains(text, "function(") {
        return false;
    }
    for byte in text.bytes() {
        if is_ident_continue(byte) or supported_punctuation(byte) {
            continue;
        }
        return false;
    }
    return true;
}

fn fallback_reason(text: string): string {
    if contains(text, "=>") {
        return "callback-argument";
    }
    if contains(text, "(") {
        return "dynamic-call-arguments";
    }
    return "complex-expression";
}

fn append_region_line(out: &List<u8>, state: &FormatState, depth: usize, kind: string, ref_id: usize, name: ?string, expression: ?string, deps: &const List<string>, paths: &const List<usize>): void {
    const id = state.next_region_id;
    state.next_region_id = state.next_region_id + 1;
    append_indent(out, depth);
    for byte in $"#{id} {kind} ref={ref_id}".bytes() {
        out.push(byte);
    }
    if name is value {
        for byte in $" name={value}".bytes() {
            out.push(byte);
        }
    }
    if expression is value {
        for byte in $" expr={value}".bytes() {
            out.push(byte);
        }
        if direct_expression(value) {
            for byte in " eval=direct".bytes() {
                out.push(byte);
            }
        } else {
            for byte in " eval=fallback".bytes() {
                out.push(byte);
            }
            const reason = fallback_reason(value);
            for byte in $" reason={reason}".bytes() {
                out.push(byte);
            }
        }
    }
    for byte in " deps=[".bytes() {
        out.push(byte);
    }
    append_list(out, deps);
    out.push(93);
    if paths.len() > 0 {
        for byte in " tracked_paths=[".bytes() {
            out.push(byte);
        }
        append_ids(out, paths);
        out.push(93);
    }
    out.push(10);
}

fn expression_dependencies(component: &const BrowserComponent, expression: Span, locals: &const List<string>): DependencyList {
    var deps = DependencyList {
        items: list<string>()
    };
    collect_expression(template_source(component), expression, &component.unit.script.facts, &component.unit.lir_document, locals, &deps, {
        retain_imported_calls: false
    });
    return deps;
}

fn expression_paths(component: &BrowserComponent, expression: Span): List<usize> {
    var paths = list<usize>();
    collect_paths(template_source(component), expression, &component.unit.script.facts, &component.unit.lir_document, &component.region_graph.table, &paths);
    return paths;
}

fn note_expression_diagnostics(component: &const BrowserComponent, state: &FormatState, expression: string, dependencies: &const List<string>): void {
    for helper in &component.unit.script.facts.state_facts.helpers {
        const call = $"{helper.name}(";
        if helper.contains_external_reads and contains(expression, call) {
            state.diagnostics.push(Diagnostic {
                severity: "warning",
                kind: "hidden-state",
                subject: expression,
                reason: "helper-contains-external-reads"
            });
        } else if helper.contains_side_effects and contains(expression, call) {
            state.diagnostics.push(Diagnostic {
                severity: "warning",
                kind: "hidden-state",
                subject: expression,
                reason: "helper-contains-side-effects"
            });
        }
    }
    if dependencies.len() == 0 and contains(expression, "(") {
        state.diagnostics.push(Diagnostic {
            severity: "warning",
            kind: "hidden-state",
            subject: expression,
            reason: "no-visible-component-dependency"
        });
    }
}

fn write_expression_region(component: &BrowserComponent, out: &List<u8>, state: &FormatState, depth: usize, kind: string, ref_id: usize, name: ?string, expression: Span, locals: &const List<string>): void {
    const dependencies = expression_dependencies(component, expression, locals);
    const paths = expression_paths(component, expression);
    const expression_text = template_text(component, expression);
    note_expression_diagnostics(component, state, expression_text, &dependencies.items);
    if direct_expression(expression_text) == false {
        state.diagnostics.push(Diagnostic {
            severity: "info",
            kind: "runtime-evaluate-fallback",
            subject: expression_text,
            reason: fallback_reason(expression_text)
        });
    }
    append_region_line(out, state, depth, kind, ref_id, name, expression_text, &dependencies.items, &paths);
}

fn write_plain_region(out: &List<u8>, state: &FormatState, depth: usize, kind: string, ref_id: usize, name: string, dependencies: &const List<string>): void {
    const paths = list<usize>();
    append_region_line(out, state, depth, kind, ref_id, name, none, dependencies, &paths);
}

fn format_region_nodes(component: &BrowserComponent, out: &List<u8>, state: &FormatState, nodes: &const List<usize>, depth: usize, locals: &const List<string>): void {
    const document = &component.render_tree;
    var i: usize = 0;
    while i < nodes.len() {
        const node = &document.nodes[nodes[i]];
        switch node.payload {
            .text(_) => {}
            .interpolation(interpolation) => {
                write_expression_region(component, out, state, depth, "text", interpolation.ref_id, none, interpolation.expression, locals);
            }
            .element(element) => {
                for effect in &element.bind_effects {
                    switch effect {
                        .bind(binding) => {
                            write_expression_region(component, out, state, depth, "attribute", element.ref_id, template_text(component, binding.name), binding.expression, locals);
                        }
                        .event(_) => {}
                    }
                }
                format_region_nodes(component, out, state, &element.children, depth, locals);
            }
            .conditional(conditional) => {
                write_expression_region(component, out, state, depth, "conditional", conditional.state_ref_id, none, conditional.condition, locals);
                format_region_nodes(component, out, state, &conditional.consequent, depth + 1, locals);
                format_region_nodes(component, out, state, &conditional.alternate, depth + 1, locals);
            }
            .for_loop(loop_node) => {
                const item_name = template_text(component, loop_node.item_name);
                write_expression_region(component, out, state, depth, "loop", loop_node.state_ref_id, item_name, loop_node.iterable_expr, locals);
                var nested_locals = list<string>();
                var local_index: usize = 0;
                while local_index < locals.len() {
                    nested_locals.push(string.from(locals[local_index].bytes()));
                    local_index = local_index + 1;
                }
                nested_locals.push(item_name);
                format_region_nodes(component, out, state, &loop_node.body, depth + 1, &nested_locals);
            }
            .component(child) => {
                var dependencies = DependencyList {
                    items: list<string>()
                };
                for effect in &child.bind_effects {
                    switch effect {
                        .bind(binding) => {
                            collect_expression(template_source(component), binding.expression, &component.unit.script.facts, &component.unit.lir_document, locals, &dependencies, {
                                retain_imported_calls: false
                            });
                        }
                        .event(_) => {}
                    }
                }
                write_plain_region(out, state, depth, "child", child.handle_ref_id, template_text(component, child.tag_name), &dependencies.items);
                for slot in &child.slot_provisions {
                    var slot_name = "default";
                    if slot.name is name_span {
                        slot_name = template_text(component, name_span);
                    }
                    const empty_deps = list<string>();
                    write_plain_region(out, state, depth + 1, "slot", child.handle_ref_id, slot_name, &empty_deps);
                    format_region_nodes(component, out, state, &slot.children, depth + 2, locals);
                }
            }
            .slot_outlet(slot) => {
                var slot_name = "default";
                if slot.name is name_span {
                    slot_name = template_text(component, name_span);
                }
                const empty_deps = list<string>();
                write_plain_region(out, state, depth, "slot", slot.handle_ref_id, slot_name, &empty_deps);
                format_region_nodes(component, out, state, &slot.fallback_children, depth + 1, locals);
            }
        }
        i = i + 1;
    }
}

fn format_runtime_regions(component: &const BrowserComponent, out: &List<u8>): void {
    var i: usize = 0;
    while i < component.region_graph.regions.len() {
        const region = &component.region_graph.regions[i];
        const kind = region_kind_label(region.kind);
        append_indent(out, 1);
        for byte in $"#{region.id} {kind} ref={region.ref_id}".bytes() {
            out.push(byte);
        }
        if region.name is name {
            for byte in $" name={name}".bytes() {
                out.push(byte);
            }
        }
        for byte in " deps=[".bytes() {
            out.push(byte);
        }
        append_list(out, &region.dependency_names);
        for byte in "] tracked_paths=[".bytes() {
            out.push(byte);
        }
        append_ids(out, &region.tracked_path_ids);
        for byte in "]\n".bytes() {
            out.push(byte);
        }
        i = i + 1;
    }
}

fn format_tracked(component: &const BrowserComponent, out: &List<u8>): void {
    if component.region_graph.table.roots.len() == 0 {
        return;
    }
    for byte in "tracked-roots\n".bytes() {
        out.push(byte);
    }
    var i: usize = 0;
    while i < component.region_graph.table.roots.len() {
        const root = &component.region_graph.table.roots[i];
        const kind = kind_label(root.kind);
        append_indent(out, 1);
        for byte in $"root id={root.id} binding={root.binding_name} kind={kind}\n".bytes() {
            out.push(byte);
        }
        i = i + 1;
    }
    for byte in "tracked-paths\n".bytes() {
        out.push(byte);
    }
    i = 0;
    while i < component.region_graph.table.paths.len() {
        const path = &component.region_graph.table.paths[i];
        append_indent(out, 1);
        for byte in $"path id={path.id} root={path.root_id} path={path.path}".bytes() {
            out.push(byte);
        }
        if path.parent_path_id is parent {
            for byte in $" parent={parent}".bytes() {
                out.push(byte);
            }
        }
        out.push(10);
        i = i + 1;
    }
}

fn format_mutations(component: &const BrowserComponent, out: &List<u8>): void {
    const script_offset = component.unit.sfc_document.script.content_span.start;
    for mutation in &component.unit.script.facts.state_facts.mutations {
        append_indent(out, 1);
        const offset = script_offset + mutation.span.start;
        for byte in $"{mutation.binding} {mutation.kind} offset={offset}\n".bytes() {
            out.push(byte);
        }
    }
}

fn format_callbacks(component: &const BrowserComponent, out: &List<u8>): void {
    const script_offset = component.unit.sfc_document.script.content_span.start;
    for registration in &component.unit.script.facts.state_facts.callback_registrations {
        append_indent(out, 1);
        var owned = "false";
        if registration.owned_candidate {
            owned = "true";
        }
        const offset = script_offset + registration.span.start;
        for byte in $"callback callee={registration.callee} kind={registration.callback_kind} owned_candidate={owned} reason={registration.reason} offset={offset}\n".bytes() {
            out.push(byte);
        }
    }
}

fn write_boundary(component: &const BrowserComponent, out: &List<u8>, depth: usize, kind: string, name: string, expression: string): void {
    append_indent(out, depth);
    for byte in $"{kind} name={name} expr={expression} owned=true".bytes() {
        out.push(byte);
    }
    if kind == "template-event" {
        const async_name = $"async function {expression}";
        if contains(script_text(component), async_name) {
            for byte in " async=true".bytes() {
                out.push(byte);
            }
        }
    }
    out.push(10);
}

fn boundary_nodes(component: &const BrowserComponent, nodes: &const List<usize>, out: &List<u8>, depth: usize): void {
    const document = &component.render_tree;
    var i: usize = 0;
    while i < nodes.len() {
        switch document.nodes[nodes[i]].payload {
            .text(_) => {}
            .interpolation(_) => {}
            .element(element) => {
                for effect in &element.event_effects {
                    switch effect {
                        .event(event) => {
                            write_boundary(component, out, depth, "template-event", template_text(component, event.name), template_text(component, event.expression));
                        }
                        .bind(_) => {}
                    }
                }
                boundary_nodes(component, &element.children, out, depth);
            }
            .conditional(branch) => {
                boundary_nodes(component, &branch.consequent, out, depth);
                boundary_nodes(component, &branch.alternate, out, depth);
            }
            .for_loop(loop_node) => {
                boundary_nodes(component, &loop_node.body, out, depth);
            }
            .component(child) => {
                for effect in &child.event_effects {
                    switch effect {
                        .event(event) => {
                            write_boundary(component, out, depth, "child-event", template_text(component, event.name), template_text(component, event.expression));
                        }
                        .bind(_) => {}
                    }
                }
                for slot in &child.slot_provisions {
                    if slot.name is name {
                        write_boundary(component, out, depth, "slot-update", template_text(component, name), "compiler-emitted");
                    } else {
                        write_boundary(component, out, depth, "slot-update", "default", "compiler-emitted");
                    }
                    boundary_nodes(component, &slot.children, out, depth + 1);
                }
            }
            .slot_outlet(slot) => {
                boundary_nodes(component, &slot.fallback_children, out, depth);
            }
        }
        i = i + 1;
    }
}

fn format_diagnostics(state: &const FormatState, out: &List<u8>): void {
    var i: usize = 0;
    if state.diagnostics.len() == 0 {
        return;
    }
    for byte in "diagnostics\n".bytes() {
        out.push(byte);
    }
    while i < state.diagnostics.len() {
        const diagnostic = &state.diagnostics[i];
        append_indent(out, 1);
        if diagnostic.reason is reason {
            for byte in $"{diagnostic.severity} {diagnostic.kind} expression={diagnostic.subject} reason={reason}\n".bytes() {
                out.push(byte);
            }
        }
        i = i + 1;
    }
}

pub fn format(component: &BrowserComponent): string {
    var out = list<u8>();
    var state = FormatState {
        next_region_id: 1,
        diagnostics: list<Diagnostic>()
    };
    for byte in $"invalidation-graph source={component.unit.source_path}\nregions\n".bytes() {
        out.push(byte);
    }
    const empty_locals = list<string>();
    format_region_nodes(component, &out, &state, &component.render_tree.roots, 1, &empty_locals);
    for byte in "runtime-regions\n".bytes() {
        out.push(byte);
    }
    format_runtime_regions(component, &out);
    format_tracked(component, &out);
    for byte in "mutations\n".bytes() {
        out.push(byte);
    }
    format_mutations(component, &out);
    for byte in "callback-registrations\n".bytes() {
        out.push(byte);
    }
    format_callbacks(component, &out);
    for byte in "boundaries\n".bytes() {
        out.push(byte);
    }
    boundary_nodes(component, &component.render_tree.roots, &out, 1);
    format_diagnostics(&state, &out);
    return string.from(out.view());
}
