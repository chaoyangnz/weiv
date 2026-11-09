// Operation: managed app diagnostics -> Zig-compatible JSON envelope.
import { append, emit_string } from .compiler.backend.browser.emit.js_module.write_javascript;
import { write_stderr, ScriptBackendError } from .ffi.script_backend;
import { Span } from .compiler.source;

pub struct DiagnosticLocation {
    pub line: usize;
    pub column: usize;
}

pub struct ProjectDiagnostic {
    pub code: string;
    pub severity: string;
    pub stage: string;
    pub message: string;
    pub source_path: string;
    pub span: ?Span;
    pub location: ?DiagnosticLocation;
    pub fatal: bool;
}

pub fn location(source: string, offset: usize): DiagnosticLocation {
    var line: usize = 1;
    var column: usize = 1;
    var cursor: usize = 0;
    const bytes = source.bytes();
    while cursor < offset and cursor < bytes.len() {
        if bytes[cursor] == 10 {
            line = line + 1;
            column = 1;
        } else {
            column = column + 1;
        }
        cursor = cursor + 1;
    }
    return DiagnosticLocation {
        line: line,
        column: column
    };
}

pub fn encode(diagnostics: &const List<ProjectDiagnostic>): string {
    var out = list<u8>();
    append(&out, "{\"mode\":\"managed-project\",\"coverage\":\"managed-template-dependencies-and-assignment-sources\",\"diagnostics\":[");
    var i: usize = 0;
    while i < diagnostics.len() {
        const diagnostic = &diagnostics[i];
        if i > 0 {
            append(&out, ",");
        }
        append(&out, "\n  {\"code\":");
        emit_string(diagnostic.code, &out);
        append(&out, ",\"severity\":");
        emit_string(diagnostic.severity, &out);
        append(&out, ",\"stage\":");
        emit_string(diagnostic.stage, &out);
        append(&out, ",\"message\":");
        emit_string(diagnostic.message, &out);
        append(&out, ",\"sourcePath\":");
        emit_string(diagnostic.source_path, &out);
        if diagnostic.span is span {
            append(&out, $",\"span\":\{\"start\":{span.start},\"end\":{span.end}\}");
        } else {
            append(&out, ",\"span\":null");
        }
        if diagnostic.location is value {
            append(&out, $",\"location\":\{\"line\":{value.line},\"column\":{value.column}\}");
        } else {
            append(&out, ",\"location\":null");
        }
        if diagnostic.fatal {
            append(&out, ",\"fatal\":true}");
        } else {
            append(&out, ",\"fatal\":false}");
        }
        i = i + 1;
    }
    if diagnostics.len() > 0 {
        append(&out, "\n");
    }
    append(&out, "]}\n");
    return string.from(out.view());
}

pub fn encode_failure(action: string, source_path: string, diagnostics: &const List<ProjectDiagnostic>): string {
    var out = list<u8>();
    append(&out, "{\n  \"action\": ");
    emit_string(action, &out);
    append(&out, ",\n  \"sourcePath\": ");
    emit_string(source_path, &out);
    append(&out, ",\n  \"ok\": false,\n  \"diagnostics\": [\n");
    var i: usize = 0;
    while i < diagnostics.len() {
        const diagnostic = &diagnostics[i];
        append(&out, "    {\n      \"code\": ");
        emit_string(diagnostic.code, &out);
        append(&out, ",\n      \"severity\": ");
        emit_string(diagnostic.severity, &out);
        append(&out, ",\n      \"stage\": ");
        emit_string(diagnostic.stage, &out);
        append(&out, ",\n      \"message\": ");
        emit_string(diagnostic.message, &out);
        append(&out, ",\n      \"sourcePath\": ");
        emit_string(diagnostic.source_path, &out);
        append(&out, ",\n");
        if diagnostic.span is span {
            append(&out, "      \"span\": { \"start\": ");
            append(&out, $"{span.start}");
            append(&out, ", \"end\": ");
            append(&out, $"{span.end}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"span\": null,\n");
        }
        if diagnostic.location is value {
            append(&out, "      \"location\": { \"line\": ");
            append(&out, $"{value.line}");
            append(&out, ", \"column\": ");
            append(&out, $"{value.column}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"location\": null,\n");
        }
        if diagnostic.fatal {
            append(&out, "      \"fatal\": true\n");
        } else {
            append(&out, "      \"fatal\": false\n");
        }
        if i + 1 < diagnostics.len() {
            append(&out, "    },\n");
        } else {
            append(&out, "    }\n");
        }
        i = i + 1;
    }
    append(&out, "  ]\n}\n");
    return string.from(out.view());
}

pub fn encode_report(source_path: string, diagnostics: &const List<ProjectDiagnostic>): string {
    var out = list<u8>();
    append(&out, "{\n  \"sourcePath\": ");
    emit_string(source_path, &out);
    append(&out, ",\n  \"mode\": \"state-boundaries\",\n  \"coverage\": \"initializers-helper-reads-and-assignment-sources\",\n  \"diagnostics\": [\n");
    var i: usize = 0;
    while i < diagnostics.len() {
        const diagnostic = &diagnostics[i];
        append(&out, "    {\n      \"code\": ");
        emit_string(diagnostic.code, &out);
        append(&out, ",\n      \"severity\": ");
        emit_string(diagnostic.severity, &out);
        append(&out, ",\n      \"stage\": ");
        emit_string(diagnostic.stage, &out);
        append(&out, ",\n      \"message\": ");
        emit_string(diagnostic.message, &out);
        append(&out, ",\n      \"sourcePath\": ");
        emit_string(diagnostic.source_path, &out);
        append(&out, ",\n");
        if diagnostic.span is span {
            append(&out, "      \"span\": { \"start\": ");
            append(&out, $"{span.start}");
            append(&out, ", \"end\": ");
            append(&out, $"{span.end}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"span\": null,\n");
        }
        if diagnostic.location is value {
            append(&out, "      \"location\": { \"line\": ");
            append(&out, $"{value.line}");
            append(&out, ", \"column\": ");
            append(&out, $"{value.column}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"location\": null,\n");
        }
        if diagnostic.fatal {
            append(&out, "      \"fatal\": true\n");
        } else {
            append(&out, "      \"fatal\": false\n");
        }
        if i + 1 < diagnostics.len() {
            append(&out, "    },\n");
        } else {
            append(&out, "    }\n");
        }
        i = i + 1;
    }
    append(&out, "  ]\n}\n");
    return string.from(out.view());
}

pub fn encode_validation(root_path: string, diagnostics: &const List<ProjectDiagnostic>): string {
    var out = list<u8>();
    append(&out, "{\n  \"rootPath\": ");
    emit_string(root_path, &out);
    var ok = true;
    for diagnostic in diagnostics {
        if diagnostic.fatal {
            ok = false;
        }
    }
    if ok {
        append(&out, ",\n  \"ok\": true,\n  \"diagnostics\": [\n");
    } else {
        append(&out, ",\n  \"ok\": false,\n  \"diagnostics\": [\n");
    }
    var i: usize = 0;
    while i < diagnostics.len() {
        const diagnostic = &diagnostics[i];
        append(&out, "    {\n      \"code\": ");
        emit_string(diagnostic.code, &out);
        append(&out, ",\n      \"severity\": ");
        emit_string(diagnostic.severity, &out);
        append(&out, ",\n      \"stage\": ");
        emit_string(diagnostic.stage, &out);
        append(&out, ",\n      \"message\": ");
        emit_string(diagnostic.message, &out);
        append(&out, ",\n      \"sourcePath\": ");
        emit_string(diagnostic.source_path, &out);
        append(&out, ",\n");
        if diagnostic.span is span {
            append(&out, "      \"span\": { \"start\": ");
            append(&out, $"{span.start}");
            append(&out, ", \"end\": ");
            append(&out, $"{span.end}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"span\": null,\n");
        }
        if diagnostic.location is value {
            append(&out, "      \"location\": { \"line\": ");
            append(&out, $"{value.line}");
            append(&out, ", \"column\": ");
            append(&out, $"{value.column}");
            append(&out, " },\n");
        } else {
            append(&out, "      \"location\": null,\n");
        }
        if diagnostic.fatal {
            append(&out, "      \"fatal\": true\n");
        } else {
            append(&out, "      \"fatal\": false\n");
        }
        if i + 1 < diagnostics.len() {
            append(&out, "    },\n");
        } else {
            append(&out, "    }\n");
        }
        i = i + 1;
    }
    append(&out, "  ]\n}\n");
    return string.from(out.view());
}

pub fn encode_text_failure(action: string, source_path: string, diagnostics: &const List<ProjectDiagnostic>): string {
    var out = list<u8>();
    append(&out, $"weiv {action} failed for {source_path}\n");
    var i: usize = 0;
    while i < diagnostics.len() {
        const diagnostic = &diagnostics[i];
        append(&out, $"  {diagnostic.severity} {diagnostic.code} [{diagnostic.stage}]");
        if diagnostic.location is value {
            append(&out, $" [{value.line}:{value.column}]");
        }
        if diagnostic.span is span {
            append(&out, $" [{span.start}..{span.end}]");
        }
        if diagnostic.fatal {
            append(&out, " fatal");
        }
        append(&out, $": {diagnostic.message}\n");
        i = i + 1;
    }
    return string.from(out.view());
}

pub fn write(diagnostics: &const List<ProjectDiagnostic>): void ! ScriptBackendError {
    try write_stderr(encode(diagnostics));
}

pub fn write_failure(action: string, source_path: string, diagnostics: &const List<ProjectDiagnostic>): void ! ScriptBackendError {
    try write_stderr(encode_failure(action, source_path, diagnostics));
}

pub fn write_text_failure(action: string, source_path: string, diagnostics: &const List<ProjectDiagnostic>): void ! ScriptBackendError {
    try write_stderr(encode_text_failure(action, source_path, diagnostics));
}
