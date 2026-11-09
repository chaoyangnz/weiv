// Address carriers avoid Cyna 0.4.1's incorrect nullable-pointer C return ABI.
// The Rust ABI and allocation ownership stay unchanged.
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

_Static_assert(sizeof(uintptr_t) == sizeof(size_t), "Address carriers require pointer-sized size_t");

extern char *weiv_script_analyze(const char *source, const char *path);
extern void weiv_backend_free(char *pointer);

uintptr_t weiv_cyna_allocate(size_t size) {
    return (uintptr_t)malloc(size);
}

void weiv_cyna_release(uintptr_t address) {
    free((void *)address);
}

void weiv_cyna_write_stderr(uintptr_t address, size_t length) {
    const char *cursor = (const char *)address;
    while (length > 0) {
        ssize_t written = write(STDERR_FILENO, cursor, length);
        if (written <= 0) return;
        cursor += (size_t)written;
        length -= (size_t)written;
    }
}

uintptr_t weiv_cyna_analyze(uintptr_t source, uintptr_t path) {
    return (uintptr_t)weiv_script_analyze((const char *)source, (const char *)path);
}

void weiv_cyna_free_response(uintptr_t address) {
    weiv_backend_free((char *)address);
}

extern char *weiv_analyze_module_state(const char *source, const char *path);
extern char *weiv_transpile_module(const char *source, const char *path);
extern char *weiv_cell_script_diagnostics(const char *source, const char *path, const char *bindings, _Bool module);
extern char *weiv_lower_module_cells(const char *source, const char *path, const char *companion, const char *bindings);
extern _Bool weiv_cell_handler_supported(const char *source);
extern uint8_t weiv_cell_handler_kind(const char *source);

uintptr_t weiv_cyna_module_state(uintptr_t source, uintptr_t path) {
    return (uintptr_t)weiv_analyze_module_state((const char *)source, (const char *)path);
}
uintptr_t weiv_cyna_transpile_module(uintptr_t source, uintptr_t path) {
    return (uintptr_t)weiv_transpile_module((const char *)source, (const char *)path);
}
uintptr_t weiv_cyna_lower_module_cells(uintptr_t source, uintptr_t path, uintptr_t companion, uintptr_t bindings) {
    return (uintptr_t)weiv_lower_module_cells((const char *)source, (const char *)path, (const char *)companion, (const char *)bindings);
}
uintptr_t weiv_cyna_cell_script_diagnostics(uintptr_t source, uintptr_t path, uintptr_t bindings, size_t module) {
    return (uintptr_t)weiv_cell_script_diagnostics((const char *)source, (const char *)path, (const char *)bindings, module != 0);
}
size_t weiv_cyna_handler_supported(uintptr_t source) {
    return weiv_cell_handler_supported((const char *)source) ? 1 : 0;
}
size_t weiv_cyna_handler_kind(uintptr_t source) {
    return weiv_cell_handler_kind((const char *)source);
}

extern char *weiv_lower_cells_with_expressions(const char *source, const char *path, const char *names, const char *expressions);
uintptr_t weiv_cyna_lower_cells(uintptr_t source, uintptr_t path, uintptr_t names, uintptr_t expressions) {
    return (uintptr_t)weiv_lower_cells_with_expressions((const char *)source, (const char *)path, (const char *)names, (const char *)expressions);
}

extern _Bool weiv_cell_expression_supported(const char *source);
size_t weiv_cyna_expression_supported(uintptr_t source) {
    return weiv_cell_expression_supported((const char *)source) ? 1 : 0;
}

// POSIX canonical path resolution for managed module identity. The caller frees
// the returned buffer with weiv_cyna_release.
uintptr_t weiv_cyna_realpath(uintptr_t path) {
    return (uintptr_t)realpath((const char *)path, NULL);
}
