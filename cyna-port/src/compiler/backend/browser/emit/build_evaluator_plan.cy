// Operation: immutable render forest/source/facts -> detached evaluator code and typed sites.
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { RenderDocument, RenderElement, RenderComponent } from .compiler.backend.browser.render_tree.tree;
import { LirDirectiveEffect } from .compiler.lower.lir;
import { EvaluatorPlan, EvaluatorRecord, EvaluatorArgument, EvaluatorSite } from .compiler.backend.browser.emit.evaluator_plan;
import { binding_names } from .compiler.lower.collect_template_functions;
import { append, TemplateFunctionError } from .compiler.lower.build_template_functions;
import { expression_supported, handler_supported } from .ffi.script_backend;

pub enum EvaluatorError {
    backend_failure;
    unsupported_render_expression;
    unsupported_handler_expression;
    reserved_identifier;
}
union EvaluatorTask {
    node: usize;
    leave_loop;
}
fn push_children(work: &List<EvaluatorTask>, children: &const List<usize>): void {
    var i = children.len();
    while i > 0 {
        i = i - 1;
        work.push(.node(children[i]));
    }
}
fn add(source: []const u8, expression: Span, node: usize, site: EvaluatorSite, effect: usize, argument: EvaluatorArgument,
    locals: &const List<string>, names: &const List<string>, output: &List<u8>, records: &List<EvaluatorRecord>
): void ! EvaluatorError {
    const text = string.from(source[expression.start..expression.end]);
    var arg: ?string = none;
    switch argument {
        EvaluatorArgument.render => {
            const supported = expression_supported(text) catch (code) {
                throw EvaluatorError.backend_failure;
            };
            if not supported {
                throw EvaluatorError.unsupported_render_expression;
            }
        }
        EvaluatorArgument.event => {
            arg = "event";
        }
        EvaluatorArgument.payload => {
            arg = "payload";
        }
    }
    if arg is name {
        const supported = handler_supported(text) catch (code) {
            throw EvaluatorError.backend_failure;
        };
        if not supported {
            throw EvaluatorError.unsupported_handler_expression;
        }
    }
    if records.len() > 0 {
        output.push(44);
    }
    const generated = append(output, text, locals, names, arg) catch (code) {
        if code == TemplateFunctionError.reserved_identifier {
            throw EvaluatorError.reserved_identifier;
        }
        throw EvaluatorError.backend_failure;
    };
    records.push(EvaluatorRecord {
        id: records.len(),
        node_id: node,
        effect_index: effect,
        site: site,
        argument: argument,
        template: expression,
        generated: generated
    });
    return;
}
fn effects(source: []const u8, list: &const List<LirDirectiveEffect>, node: usize, argument: EvaluatorArgument,
    locals: &const List<string>, names: &const List<string>, output: &List<u8>, records: &List<EvaluatorRecord>
): void ! EvaluatorError {
    var i: usize = 0;
    while i < list.len() {
        const effect = &list[i];
        switch effect {
            .bind(value) => {
                try add(source, value.expression, node, EvaluatorSite.binding, i, EvaluatorArgument.render, locals, names, output, records);
            }
            .event(value) => {
                try add(source, value.expression, node, EvaluatorSite.handler, i, argument, locals, names, output, records);
            }
        }
        i = i + 1;
    }
    return;
}
fn element(source: []const u8, value: &const RenderElement, id: usize, locals: &const List<string>, names: &const List<string>, output: &List<u8>, records: &List<EvaluatorRecord>, work: &List<EvaluatorTask>): void ! EvaluatorError {
    try effects(source, &value.bind_effects, id, EvaluatorArgument.event, locals, names, output, records);
    try effects(source, &value.event_effects, id, EvaluatorArgument.event, locals, names, output, records);
    push_children(work, &value.children);
    return;
}
fn component(source: []const u8, value: &const RenderComponent, id: usize, locals: &const List<string>, names: &const List<string>, output: &List<u8>, records: &List<EvaluatorRecord>, work: &List<EvaluatorTask>): void ! EvaluatorError {
    try effects(source, &value.bind_effects, id, EvaluatorArgument.payload, locals, names, output, records);
    try effects(source, &value.event_effects, id, EvaluatorArgument.payload, locals, names, output, records);
    var i = value.slot_provisions.len();
    while i > 0 {
        i = i - 1;
        push_children(work, &value.slot_provisions[i].children);
    }
    return;
}
pub fn build(source: []const u8, tree: &const RenderDocument, script: &const ScriptFacts): EvaluatorPlan ! EvaluatorError {
    const names = binding_names(script);
    var locals = list<string>();
    var output = list<u8>();
    var records = list<EvaluatorRecord>();
    var work = list<EvaluatorTask>();
    push_children(&work, &tree.roots);
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
                        try add(source, value.expression, id, EvaluatorSite.interpolation, 0, EvaluatorArgument.render, &locals, &names, &output, &records);
                    }
                    .element(value) => {
                        try element(source, &value, id, &locals, &names, &output, &records, &work);
                    }
                    .component(value) => {
                        try component(source, &value, id, &locals, &names, &output, &records, &work);
                    }
                    .conditional(value) => {
                        try add(source, value.condition, id, EvaluatorSite.condition, 0, EvaluatorArgument.render, &locals, &names, &output, &records);
                        push_children(&work, &value.alternate);
                        push_children(&work, &value.consequent);
                    }
                    .for_loop(value) => {
                        try add(source, value.iterable_expr, id, EvaluatorSite.iterable, 0, EvaluatorArgument.render, &locals, &names, &output, &records);
                        locals.push(string.from(source[value.item_name.start..value.item_name.end]));
                        work.push(.leave_loop);
                        push_children(&work, &value.body);
                    }
                    .slot_outlet(value) => {
                        push_children(&work, &value.fallback_children);
                    }
                }
            }
        }
    }
    return {
        code: string.from(output.view()),
        records: records
    };
}
