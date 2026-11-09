// Operation: owned browser project artifacts -> directory tree and files.
import { ProjectBuild, ProjectModule } from .compiler.project.project_build;
import { ProjectDiagnostic } from .compiler.project.diagnostics;
import { normalize, PathError } from .compiler.project.resolve_component_path;
import std.fs;
import std.mem;
import { append } from .compiler.backend.browser.emit.js_module.write_javascript;
import { emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { analyze_module_state_raw } from .ffi.script_backend;
import std.json;
import { Value } from std.json;
import { ScriptDecodeError } from .compiler.sema.script_json;
import .compiler.sema.script_json as validation;
import { Span } from .compiler.source;

pub enum WriteError {
    invalid_path;
    filesystem;
    import_analysis;
}

struct SourceReference {
    source: string;
    span: Span;
}

fn decode_source(value: &const Value): SourceReference ! ScriptDecodeError {
    return switch value {
        .object(object) => SourceReference {
            source: try validation.text_field(&object, "source"),
            span: try validation.span(&object, "span_start", "span_end")
        };
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

fn relative_runtime_path(module_path: string, name: string): string {
    var prefix = list<u8>();
    for byte in module_path.bytes() {
        if byte == 47 {
            append(&prefix, "../");
        }
    }
    if prefix.len() == 0 {
        append(&prefix, "./");
    }
    append(&prefix, "__weiv_runtime/");
    append(&prefix, name);
    return string.from(prefix.view());
}

fn rewrite_virtual_imports(code: string, module_path: string): string ! WriteError {
    const raw = analyze_module_state_raw(code, module_path) catch (error) {
        throw WriteError.import_analysis;
    };
    const value = json.parse(raw) catch (error) {
        throw WriteError.import_analysis;
    };
    var references = list<SourceReference>();
    switch value {
        .object(object) => {
            references = validation.record_field<SourceReference>(&object, "sources", decode_source) catch (error) {
                throw WriteError.import_analysis;
            };
        }
        _ => {
            throw WriteError.import_analysis;
        }
    }
    var out = list<u8>();
    var cursor: usize = 0;
    var i: usize = 0;
    const bytes = code.bytes();
    while i < references.len() {
        const reference = &references[i];
        if reference.span.start < cursor or reference.span.end > bytes.len() {
            throw WriteError.import_analysis;
        }
        append(&out, string.from(bytes[cursor..reference.span.start]));
        var target: ?string = none;
        if reference.source == "weiv:cells" {
            target = relative_runtime_path(module_path, "cell.js");
        } else if reference.source == "weiv:observable" {
            target = relative_runtime_path(module_path, "observable.js");
        } else if reference.source == "weiv:router" {
            target = relative_runtime_path(module_path, "router.js");
        }
        if target is path {
            emit_string(path, &out);
        } else {
            append(&out, string.from(bytes[reference.span.start..reference.span.end]));
        }
        cursor = reference.span.end;
        i = i + 1;
    }
    append(&out, string.from(bytes[cursor..]));
    return string.from(out.view());
}

pub fn write_with_runtime(build: &const ProjectBuild, output_dir: string, runtime_dir: string): void ! WriteError {
    const root = normalize(output_dir) catch (code) {
        throw WriteError.invalid_path;
    };
    const runtime = normalize(runtime_dir) catch (code) {
        throw WriteError.invalid_path;
    };
    const names: [6]string = ["binding.js", "cell.js", "index.js", "observable.js", "reactive-core.js", "router.js"];
    var runtime_sources = list<string>();
    for name in names {
        const present = fs.exists($"{runtime}/{name}") catch (code) {
            throw WriteError.filesystem;
        };
        if not present {
            throw WriteError.filesystem;
        }
        const source = fs.read_file($"{runtime}/{name}") catch (code) {
            throw WriteError.filesystem;
        };
        runtime_sources.push(source);
    }
    var rewritten = ProjectBuild {
        entry_module: string.from(build.entry_module.bytes()),
        modules: list<ProjectModule>(),
        stylesheet: string.from(build.stylesheet.bytes()),
        diagnostics: list<ProjectDiagnostic>()
    };
    var i: usize = 0;
    while i < build.modules.len() {
        const artifact = &build.modules[i];
        rewritten.modules.push(ProjectModule {
            source_path: string.from(artifact.source_path.bytes()),
            module_path: string.from(artifact.module_path.bytes()),
            code: try rewrite_virtual_imports(artifact.code, artifact.module_path),
            css: string.from(artifact.css.bytes())
        });
        i = i + 1;
    }
    try write(&rewritten, root);
    const target = $"{root}/__weiv_runtime";
    try ensure_directory(target);
    i = 0;
    while i < 6 {
        const name = names[i];
        fs.write_file($"{target}/{name}", runtime_sources[i]) catch (code) {
            throw WriteError.filesystem;
        };
        i = i + 1;
    }
    return;
}

fn ensure_directory(path: string): void ! WriteError {
    const normalized = normalize(path) catch (code) {
        throw WriteError.invalid_path;
    };
    const bytes = normalized.bytes();
    var i: usize = 1;
    while i <= bytes.len() {
        if i == bytes.len() or bytes[i] == 47 {
            const current = string.from(bytes[..i]);
            const exists = fs.exists(current) catch (code) {
                throw WriteError.filesystem;
            };
            if not exists {
                fs.create_dir(current) catch (code) {
                    throw WriteError.filesystem;
                };
            }
        }
        i = i + 1;
    }
    return;
}

pub fn write(build: &const ProjectBuild, output_dir: string): void ! WriteError {
    const root = normalize(output_dir) catch (code) {
        throw WriteError.invalid_path;
    };
    // Validate every destination before creating any directory or writing a file.
    var i: usize = 0;
    while i < build.modules.len() {
        const artifact = &build.modules[i];
        const path = normalize($"{root}/{artifact.module_path}") catch (code) {
            throw WriteError.invalid_path;
        };
        if not mem.starts_with(path.bytes(), $"{root}/".bytes()) {
            throw WriteError.invalid_path;
        }
        i = i + 1;
    }
    try ensure_directory(root);
    i = 0;
    while i < build.modules.len() {
        const artifact = &build.modules[i];
        const path = normalize($"{root}/{artifact.module_path}") catch (code) {
            throw WriteError.invalid_path;
        };
        var last: usize = 0;
        var j: usize = 0;
        const bytes = path.bytes();
        while j < bytes.len() {
            if bytes[j] == 47 {
                last = j;
            }
            j = j + 1;
        }
        try ensure_directory(string.from(bytes[..last]));
        fs.write_file(path, artifact.code) catch (code) {
            throw WriteError.filesystem;
        };
        i = i + 1;
    }
    fs.write_file($"{root}/styles.css", build.stylesheet) catch (code) {
        throw WriteError.filesystem;
    };
    return;
}
