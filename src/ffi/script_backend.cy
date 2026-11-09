pub enum ScriptBackendError {
    embedded_nul;
    allocation_failure;
    backend_failure;
}

// Native addresses are carried as c_size_t until nullable C pointer ABI is fixed.
extern c("weiv_cyna_allocate") fn allocate(size: c_size_t): c_size_t;
extern c("weiv_cyna_release") fn release(address: c_size_t): void;
extern c("weiv_cyna_write_stderr") fn native_write_stderr(address: c_size_t, length: c_size_t): void;
extern c("weiv_cyna_analyze") fn script_analyze(source: c_size_t, path: c_size_t): c_size_t;
extern c("weiv_cyna_free_response") fn backend_free(address: c_size_t): void;

fn contains_nul(text: string): bool {
    for byte in text.bytes() {
        if byte == 0 {
            return true;
        }
    }
    return false;
}

fn make_buffer(text: string): c_size_t ! ScriptBackendError {
    const allocation = allocate((text.bytes().len() + 1) as c_size_t);
    if allocation == 0 {
        throw ScriptBackendError.allocation_failure;
    }
    unchecked {
        const pointer = allocation as! *c_char;
        var index: usize = 0;
        for byte in text.bytes() {
            *(pointer + index) = byte as! c_char;
            index = index + 1;
        }
        * (pointer + index) = 0;
        return allocation;
    }
}

fn copy_output(address: c_size_t): string {
    var bytes = list<u8>();
    // Rust guarantees a valid, NUL-terminated CString until backend_free.
    unchecked {
        const pointer = address as! *const c_char;
        var index: usize = 0;
        var byte = *(pointer + index);
        while byte != 0 {
            bytes.push(byte as! u8);
            index = index + 1;
            byte = *(pointer + index);
        }
    }
    return string.from(bytes.view());
}

pub fn write_stderr(text: string): void ! ScriptBackendError {
    if contains_nul(text) {
        throw ScriptBackendError.embedded_nul;
    }
    const buffer = try make_buffer(text);
    defer release(buffer);
    native_write_stderr(buffer, text.bytes().len() as c_size_t);
}

pub fn analyze_raw(source: string, source_path: string): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(source_path) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(source_path);
    defer release(path_buffer);
    const response = script_analyze(source_buffer, path_buffer);
    return try take_response(response);
}

pub fn take_response(response: c_size_t): string ! ScriptBackendError {
    if response == 0 {
        throw ScriptBackendError.backend_failure;
    }
    defer backend_free(response);
    return copy_output(response);
}

extern c("weiv_cyna_module_state") fn module_state(source: c_size_t, path: c_size_t): c_size_t;
extern c("weiv_cyna_transpile_module") fn transpile_module(source: c_size_t, path: c_size_t): c_size_t;
extern c("weiv_cyna_cell_script_diagnostics") fn cell_script_diagnostics(source: c_size_t, path: c_size_t, bindings: c_size_t, is_module: c_size_t): c_size_t;
extern c("weiv_cyna_lower_module_cells") fn lower_module_cells(source: c_size_t, path: c_size_t, companion: c_size_t, bindings: c_size_t): c_size_t;
extern c("weiv_cyna_handler_supported") fn supported(source: c_size_t): c_size_t;
extern c("weiv_cyna_handler_kind") fn kind(source: c_size_t): c_size_t;

pub fn analyze_module_state_raw(source: string, source_path: string): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(source_path) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(source_path);
    defer release(path_buffer);
    return try take_response(module_state(source_buffer, path_buffer));
}
pub fn transpile_module_raw(source: string, source_path: string): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(source_path) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(source_path);
    defer release(path_buffer);
    return try take_response(transpile_module(source_buffer, path_buffer));
}
pub fn cell_script_diagnostics_raw(source: string, source_path: string, bindings: string, is_module: bool): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(source_path) or contains_nul(bindings) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(source_path);
    defer release(path_buffer);
    const bindings_buffer = try make_buffer(bindings);
    defer release(bindings_buffer);
    var module_flag: c_size_t = 0;
    if is_module {
        module_flag = 1;
    }
    return try take_response(cell_script_diagnostics(source_buffer, path_buffer, bindings_buffer, module_flag));
}
pub fn lower_module_cells_raw(source: string, source_path: string, companion: string, bindings: string): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(source_path) or contains_nul(companion) or contains_nul(bindings) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(source_path);
    defer release(path_buffer);
    const companion_buffer = try make_buffer(companion);
    defer release(companion_buffer);
    const bindings_buffer = try make_buffer(bindings);
    defer release(bindings_buffer);
    return try take_response(lower_module_cells(source_buffer, path_buffer, companion_buffer, bindings_buffer));
}
pub fn handler_supported(source: string): bool ! ScriptBackendError {
    if contains_nul(source) {
        throw ScriptBackendError.embedded_nul;
    }
    const buffer = try make_buffer(source);
    defer release(buffer);
    return supported(buffer) != 0;
}
pub fn handler_kind(source: string): u8 ! ScriptBackendError {
    if contains_nul(source) {
        throw ScriptBackendError.embedded_nul;
    }
    const buffer = try make_buffer(source);
    defer release(buffer);
    return kind(buffer) as u8;
}

extern c("weiv_cyna_lower_cells") fn lower_cells(source: c_size_t, path: c_size_t, names: c_size_t, expressions: c_size_t): c_size_t;
pub fn lower_cells_raw(source: string, path: string, names: string, expressions: string): string ! ScriptBackendError {
    if contains_nul(source) or contains_nul(path) or contains_nul(names) or contains_nul(expressions) {
        throw ScriptBackendError.embedded_nul;
    }
    const source_buffer = try make_buffer(source);
    defer release(source_buffer);
    const path_buffer = try make_buffer(path);
    defer release(path_buffer);
    const names_buffer = try make_buffer(names);
    defer release(names_buffer);
    const expression_buffer = try make_buffer(expressions);
    defer release(expression_buffer);
    return try take_response(lower_cells(source_buffer, path_buffer, names_buffer, expression_buffer));
}

extern c("weiv_cyna_expression_supported") fn expression_valid(source: c_size_t): c_size_t;
pub fn expression_supported(source: string): bool ! ScriptBackendError {
    if contains_nul(source) {
        throw ScriptBackendError.embedded_nul;
    }
    const buffer = try make_buffer(source);
    defer release(buffer);
    return expression_valid(buffer) != 0;
}

extern c("weiv_cyna_realpath") fn native_realpath(path: c_size_t): c_size_t;
// POSIX canonical path of an existing file. Returns an empty string when absent.
pub fn canonical_path(path: string): string ! ScriptBackendError {
    if contains_nul(path) {
        throw ScriptBackendError.embedded_nul;
    }
    const buffer = try make_buffer(path);
    defer release(buffer);
    const result = native_realpath(buffer);
    if result == 0 {
        return "";
    }
    defer release(result);
    return copy_output(result);
}
