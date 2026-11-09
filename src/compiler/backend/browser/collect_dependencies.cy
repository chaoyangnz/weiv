// Operation: script/LIR/expression or browser subtree -> ordered owned dependencies.
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { LirDocument, LirDirectiveEffect } from .compiler.lower.lir;
import { RenderDocument, RenderElement, RenderComponent, RenderConditional, RenderForLoop, RenderSlotOutlet } from .compiler.backend.browser.render_tree.tree;
import { DependencyList } from .compiler.backend.browser.dependencies;
import { is_imported, find_visible_binding } from .compiler.backend.browser.classify_tracked_roots;

pub struct DependencyOptions {
    pub retain_imported_calls: bool;
}
struct HelperFrame {
    id: usize;
    next_call: usize;
    entered: bool;
}
union NodeTask {
    node: usize;
    leave_loop;
}
fn contains(names: &const List<string>, name: string): bool {
    var i: usize = 0;
    while i < names.len() {
        if names[i] == name {
            return true;
        }
        i = i + 1;
    }
    return false;
}
fn append_unique(deps: &DependencyList, name: string): void {
    if not deps.contains(name) {
        deps.items.push(name);
    }
}
fn helper_id(script: &const ScriptFacts, name: string): ?usize {
    var i: usize = 0;
    while i < script.state_facts.helpers.len() {
        const helper = &script.state_facts.helpers[i];
        if helper.name == name {
            return i;
        }
        i = i + 1;
    }
    return none;
}
// Reads precede calls; each call expands before its next sibling. Trail is path-local.
fn collect_helper(script: &const ScriptFacts, name: string, deps: &DependencyList): void {
    var work = list<HelperFrame>();
    if helper_id(script, name) is id {
        work.push(HelperFrame {
            id: id,
            next_call: 0,
            entered: false
        });
    }
    var trail = list<string>();
    while work.len() > 0 {
        var frame = work.pop();
        const helper = &script.state_facts.helpers[frame.id];
        if not frame.entered {
            var r: usize = 0;
            while r < helper.reads.len() {
                append_unique(deps, string.from(helper.reads[r].bytes()));
                r = r + 1;
            }
            trail.push(helper.name);
            frame.entered = true;
        }
        if frame.next_call >= helper.calls.len() {
            const _ = trail.pop();
        } else {
            const called = string.from(helper.calls[frame.next_call].bytes());
            frame.next_call = frame.next_call + 1;
            work.push(frame);
            append_unique(deps, called);
            if not contains(&trail, called) {
                if find_visible_binding(script, called) is index {
                    const binding = &script.bindings[index];
                    if binding.callable {
                        if helper_id(script, called) is id {
                            work.push(HelperFrame {
                                id: id,
                                next_call: 0,
                                entered: false
                            });
                        }
                    }
                }
            }
        }
    }
}
fn reference(script: &const ScriptFacts, name: string, call: bool, locals: &const List<string>, deps: &DependencyList, options: DependencyOptions): void {
    if call and not options.retain_imported_calls and is_imported(script, name) {
        return;
    }
    if call {
        if find_visible_binding(script, name) is index {
            const binding = &script.bindings[index];
            append_unique(deps, name);
            if binding.callable {
                collect_helper(script, name, deps);
            }
            return;
        }
    }
    if find_visible_binding(script, name) is index {
        append_unique(deps, name);
    } else if contains(locals, name) {
        append_unique(deps, name);
    }
}
fn ident_start(byte: u8): bool {
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 or byte == 36;
}
fn ident_continue(byte: u8): bool {
    return ident_start(byte) or (byte >= 48 and byte <= 57);
}
fn space(byte: u8): bool {
    return byte == 32 or byte == 10 or byte == 13 or byte == 9;
}
fn call_after(bytes: []const u8, start: usize): bool {
    var i = start;
    while i < bytes.len() and space(bytes[i]) {
        i = i + 1;
    }
    return i < bytes.len() and bytes[i] == 40;
}
fn property(bytes: []const u8, start: usize): bool {
    var i = start;
    while i > 0 {
        i = i - 1;
        if not space(bytes[i]) {
            if bytes[i] != 46 {
                return false;
            }
            return not (i >= 2 and bytes[i - 1] == 46 and bytes[i - 2] == 46);
        }
    }
    return false;
}
fn keyword(name: string): bool {
    return name == "true" or name == "false" or name == "null" or name == "undefined" or name == "typeof" or name == "instanceof" or name == "return" or name == "new" or name == "await";
}

pub fn collect_expression(source: []const u8, span: Span, script: &const ScriptFacts, document: &const LirDocument, locals: &const List<string>, deps: &DependencyList, options: DependencyOptions): void {
    if document.find_expression(span) is id {
        const expression = &document.expressions[id];
        var r: usize = 0;
        while r < expression.references.len() {
            const item = &expression.references[r];
            reference(script, item.name, item.call, locals, deps, options);
            r = r + 1;
        }
        return;
    }
    const bytes = source[span.start..span.end];
    var i: usize = 0;
    while i < bytes.len() {
        if not ident_start(bytes[i]) {
            i = i + 1;
            continue;
        }
        const start = i;
        i = i + 1;
        while i < bytes.len() and ident_continue(bytes[i]) {
            i = i + 1;
        }
        const name = string.from(bytes[start..i]);
        if not keyword(name) and not property(bytes, start) {
            reference(script, name, call_after(bytes, i), locals, deps, options);
        }
    }
}
pub fn retain_visible(script: &const ScriptFacts, deps: &DependencyList): void {
    var retained = list<string>();
    var i: usize = 0;
    while i < deps.items.len() {
        const name = string.from(deps.items[i].bytes());
        if find_visible_binding(script, name) is index {
            retained.push(name);
        }
        i = i + 1;
    }
    deps.items = retained;
}
fn push_children(work: &List<NodeTask>, children: &const List<usize>): void {
    var i = children.len();
    while i > 0 {
        i = i - 1;
        work.push(.node(children[i]));
    }
}
fn queue_conditional(work: &List<NodeTask>, value: &const RenderConditional): void {
    push_children(work, &value.alternate);
    push_children(work, &value.consequent);
}
fn queue_loop(work: &List<NodeTask>, value: &const RenderForLoop): void {
    push_children(work, &value.body);
}
fn queue_outlet(work: &List<NodeTask>, value: &const RenderSlotOutlet): void {
    push_children(work, &value.fallback_children);
}
fn effects(source: []const u8, script: &const ScriptFacts, document: &const LirDocument, list: &const List<LirDirectiveEffect>, include_events: bool, locals: &const List<string>, deps: &DependencyList, options: DependencyOptions): void {
    var i: usize = 0;
    while i < list.len() {
        const effect = &list[i];
        switch effect {
            .bind(value) => {
                collect_expression(source, value.expression, script, document, locals, deps, options);
            }
            .event(value) => {
                if include_events {
                    collect_expression(source, value.expression, script, document, locals, deps, options);
                }
            }
        }
        i = i + 1;
    }
}
fn element(source: []const u8, script: &const ScriptFacts, document: &const LirDocument, value: &const RenderElement, locals: &const List<string>, deps: &DependencyList, options: DependencyOptions, work: &List<NodeTask>): void {
    effects(source, script, document, &value.bind_effects, false, locals, deps, options);
    push_children(work, &value.children);
}
fn component(source: []const u8, script: &const ScriptFacts, document: &const LirDocument, value: &const RenderComponent, locals: &const List<string>, deps: &DependencyList, options: DependencyOptions, work: &List<NodeTask>): void {
    effects(source, script, document, &value.bind_effects, true, locals, deps, options);
    effects(source, script, document, &value.event_effects, true, locals, deps, options);
    var p = value.slot_provisions.len();
    while p > 0 {
        p = p - 1;
        const slot = &value.slot_provisions[p];
        push_children(work, &slot.children);
    }
}
// Collects one subtree so region planning can control structural ownership.
pub fn collect_node(source: []const u8, script: &const ScriptFacts, document: &const LirDocument, tree: &const RenderDocument, node_id: usize, loop_locals: &const List<string>, deps: &DependencyList, options: DependencyOptions): void {
    var locals = list<string>();
    var i: usize = 0;
    while i < loop_locals.len() {
        locals.push(string.from(loop_locals[i].bytes()));
        i = i + 1;
    }
    var work = list<NodeTask>();
    work.push(.node(node_id));
    while work.len() > 0 {
        const task = work.pop();
        switch task {
            .leave_loop => {
                const _ = locals.pop();
            }
            .node(id) => {
                const payload = &tree.nodes[id].payload;
                switch payload {
                    .text(value) => {}
                    .interpolation(value) => {
                        collect_expression(source, value.expression, script, document, &locals, deps, options);
                    }
                    .element(value) => {
                        element(source, script, document, &value, &locals, deps, options, &work);
                    }
                    .component(value) => {
                        component(source, script, document, &value, &locals, deps, options, &work);
                    }
                    .conditional(value) => {
                        collect_expression(source, value.condition, script, document, &locals, deps, options);
                        queue_conditional(&work, &value);
                    }
                    .for_loop(value) => {
                        collect_expression(source, value.iterable_expr, script, document, &locals, deps, options);
                        locals.push(string.from(source[value.item_name.start..value.item_name.end]));
                        work.push(.leave_loop);
                        queue_loop(&work, &value);
                    }
                    .slot_outlet(value) => {
                        queue_outlet(&work, &value);
                    }
                }
            }
        }
    }
}
