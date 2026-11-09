// Operation: script facts/source/evaluators and selected state -> setup code.
import { ComponentUnit } from .compiler.component_unit;
import { lower_cells_raw } from .ffi.script_backend;
import { decode } from .compiler.backend.browser.emit.js_module.decode_cell_output;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import { should_preserve } from .compiler.backend.browser.emit.js_module.emit_module_imports;
import .compiler.backend.browser.emit.js_module.module_fragments as fragments;
import std.mem;
import { CellSelection } from .compiler.backend.browser.emit.cell_selection;
import { select, is_selected } from .compiler.backend.browser.emit.js_module.select_cells;
import { emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;

pub fn emit(unit: &const ComponentUnit, evaluators: string, selection: &const CellSelection): string ! JavaScriptError {
    var out = list<u8>();
    append(&out, fragments.setup_header());
    const bytes = unit.source.bytes();
    const script = string.from(bytes[unit.sfc_document.script.content_span.start..unit.sfc_document.script.content_span.end]);
    const names = try select(unit, selection);
    const payload = lower_cells_raw(script, unit.source_path, names, evaluators) catch (code) {
        throw JavaScriptError.backend_failure;
    };
    append(&out, try decode(payload));
    append(&out, "\n");
    append(&out, "  const __weiv_scope = {__proto__: null};\n");
    if evaluators.bytes().len() > 0 {
        append(&out, "  __weiv_scope.__weiv_eval = __weiv_templateExpressions;\n");
    }
    append(&out, "  function __weiv_refresh() {\n    __weiv_scope.props = props;\n    __weiv_scope.emit = emit;\n");
    var i: usize = 0;
    while i < unit.script.facts.imports.len() {
        const record = &unit.script.facts.imports[i];
        if record.local_name.bytes().len() > 0 and not mem.ends_with(record.source.bytes(), ".weiv".bytes()) and should_preserve(record, &unit.script.facts) {
            const name = record.local_name;
            append(&out, $"    __weiv_scope.{name} = __weiv_import_{name};\n");
        }
        i = i + 1;
    }
    i = 0;
    while i < unit.script.facts.bindings.len() {
        const binding = &unit.script.facts.bindings[i];
        if binding.template_visible and binding.kind != "import" {
            const name = binding.name;
            if is_selected(selection, name) {
                append(&out, $"    __weiv_scope.{name} = {name}.value;\n");
            } else {
                append(&out, $"    __weiv_scope.{name} = {name};\n");
            }
        }
        i = i + 1;
    }
    append(&out, "    return __weiv_scope;\n  }\n  function __weiv_setProps(nextProps) {\n    __weiv_propsCell.value = nextProps;\n    props = __weiv_propsCell.value;\n  }\n  function __weiv_setEventHandlers(nextHandlers) {\n    __weiv_handlers = nextHandlers;\n  }\n  function __weiv_subscribeImportedObservables(__weiv_instance) {\n    const __weiv_cellScope = __weiv_createCellScope((dirty) => { if (!__weiv_instance.destroyed) __weiv_instance.updateDirty({ bindings: [...dirty], paths: [] }, __weiv_instance.refresh()); });\n    __weiv_cellScope.watch(__weiv_propsCell, \"props\");\n");
    var subscription_index: usize = 0;
    while subscription_index < selection.local_subscriptions.len() {
        const subscription = &selection.local_subscriptions[subscription_index];
        if is_selected(selection, subscription.name) {
            append(&out, $"    __weiv_cellScope.watch({subscription.name}, ");
            emit_string(subscription.binding, &out);
            append(&out, ");\n");
        }
        subscription_index = subscription_index + 1;
    }
    var publisher_index: usize = 0;
    subscription_index = 0;
    while subscription_index < selection.managed_subscriptions.len() {
        const subscription = &selection.managed_subscriptions[subscription_index];
        append(&out, $"    __weiv_cellScope.watch(__weiv_publisher_{publisher_index}.getCell(");
        emit_string(subscription.name, &out);
        append(&out, "), ");
        emit_string(subscription.binding, &out);
        append(&out, ");\n");
        publisher_index = publisher_index + 1;
        subscription_index = subscription_index + 1;
    }
    var import_index: usize = 0;
    while import_index < unit.script.facts.imports.len() {
        const record = &unit.script.facts.imports[import_index];
        if record.local_name.bytes().len() > 0 and not mem.ends_with(record.source.bytes(), ".weiv".bytes()) and should_preserve(record, &unit.script.facts) {
            var publisher_backed = false;
            var watched = false;
            subscription_index = 0;
            while subscription_index < selection.local_subscriptions.len() {
                const subscription = &selection.local_subscriptions[subscription_index];
                if subscription.name == record.local_name {
                    if subscription.publisher_backed {
                        publisher_backed = true;
                    }
                    watched = true;
                }
                subscription_index = subscription_index + 1;
            }
            if watched and not publisher_backed {
                const name = record.local_name;
                append(&out, $"    if (__weiv_isObservable(__weiv_import_{name})) \{ const __weiv_importedCell = __weiv_createCell(__weiv_import_{name});\n");
                subscription_index = 0;
                while subscription_index < selection.local_subscriptions.len() {
                    const subscription = &selection.local_subscriptions[subscription_index];
                    if subscription.name == name {
                        append(&out, "      __weiv_cellScope.watch(__weiv_importedCell, ");
                        emit_string(subscription.binding, &out);
                        append(&out, ");\n");
                    }
                    subscription_index = subscription_index + 1;
                }
                append(&out, "    }\n");
            }
        }
        import_index = import_index + 1;
    }
    append(&out, "    return () => __weiv_cellScope.dispose();\n  }\n  return { scope: __weiv_scope, refresh: __weiv_refresh, setProps: __weiv_setProps, setEventHandlers: __weiv_setEventHandlers, subscribeImportedObservables: __weiv_subscribeImportedObservables };\n}\n");
    return string.from(out.view());
}
