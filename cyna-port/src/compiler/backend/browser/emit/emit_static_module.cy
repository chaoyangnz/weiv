// Compatibility operation: validate static-only input, then use the shared module emitter.
import { BrowserComponent } from .compiler.backend.browser.component;
import { ImportOverride, JavaScriptModule } from .compiler.backend.browser.emit.javascript_module;
import { JavaScriptError } from .compiler.backend.browser.emit.javascript_errors;
import { validate_static as validate } from .compiler.backend.browser.emit.js_module.emit_dom;
import { emit as emit_module } from .compiler.backend.browser.emit.emit_module;
pub fn emit(component: &const BrowserComponent, overrides: &const List<ImportOverride>): JavaScriptModule ! JavaScriptError {
    try validate(&component.render_tree);
    return try emit_module(component, overrides);
}
