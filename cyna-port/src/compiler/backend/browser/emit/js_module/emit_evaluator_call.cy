// Operation: typed evaluator reference -> JavaScript invocation, never a source sentinel.
import { EvaluatorRecord, EvaluatorArgument } from .compiler.backend.browser.emit.evaluator_plan;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
pub fn emit(record: &const EvaluatorRecord, scope: string): string {
    var output = list<u8>();
    const id = record.id;
    append(&output, $"((__weiv_context) => __weiv_context.__weiv_eval[{id}](__weiv_context");
    switch record.argument {
        EvaluatorArgument.render => {}
        EvaluatorArgument.event => {
            append(&output, ", event");
        }
        EvaluatorArgument.payload => {
            append(&output, ", payload");
        }
    }
    append(&output, $"))({scope})");
    return string.from(output.view());
}
