// Operation: expression source + facts -> append stable canonical paths and unique leaf IDs.
import { Span } from .compiler.source;
import { ScriptFacts } from .compiler.sema.script_facts;
import { LirDocument } from .compiler.lower.lir;
import { TrackedKind, TrackedRoot } from .compiler.backend.browser.tracked_roots;
import { TrackedPath, TrackedPaths } from .compiler.backend.browser.tracked_paths;
import { kind_by_name } from .compiler.backend.browser.classify_tracked_roots;

fn ident_start(byte: u8): bool {
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95 or byte == 36;
}
fn ident_continue(byte: u8): bool {
    return ident_start(byte) or (byte >= 48 and byte <= 57);
}
fn space(byte: u8): bool {
    return byte == 32 or byte == 10 or byte == 13 or byte == 9;
}
fn next_non_space(bytes: []const u8, start: usize): ?usize {
    var i = start;
    while i < bytes.len() {
        if not space(bytes[i]) {
            return i;
        }
        i = i + 1;
    }
    return none;
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
fn append_unique(ids: &List<usize>, id: usize): void {
    var i: usize = 0;
    while i < ids.len() {
        if ids[i] == id {
            return;
        }
        i = i + 1;
    }
    ids.push(id);
}
fn ensure_root(table: &TrackedPaths, name: string, kind: TrackedKind): usize {
    if table.find_root(name) is id {
        return id;
    }
    const id = table.roots.len() + 1;
    table.roots.push(TrackedRoot {
        id: id,
        binding_name: name,
        kind: kind
    });
    return id;
}
fn ensure_chain(table: &TrackedPaths, path: string, root_name: string, kind: TrackedKind): usize {
    if table.find_path(path) is id {
        return id;
    }
    const root = ensure_root(table, root_name, kind);
    const bytes = path.bytes();
    var parent: ?usize = none;
    var end: usize = 0;
    while end <= bytes.len() {
        if end == bytes.len() or bytes[end] == 46 {
            const prefix = string.from(bytes[..end]);
            var id: usize = 0;
            if table.find_path(prefix) is existing {
                id = existing;
            } else {
                id = table.paths.len() + 1;
                table.paths.push(TrackedPath {
                    id: id,
                    root_id: root,
                    path: prefix,
                    parent_path_id: parent
                });
            }
            parent = id;
            if end == bytes.len() {
                return id;
            }
        }
        end = end + 1;
    }
    panic("Canonical path chain must include its leaf");
}
fn referenced(document: &const LirDocument, expression_id: usize, name: string): bool {
    const expression = &document.expressions[expression_id];
    var r: usize = 0;
    while r < expression.references.len() {
        const reference = &expression.references[r];
        if reference.name == name {
            return true;
        }
        r = r + 1;
    }
    return false;
}

// The caller retains the immutable facts/LIR across an ordered collection session.
// source/span identify the same template snapshot used by document expression facts.
pub fn collect(source: []const u8, span: Span, script: &const ScriptFacts, document: &const LirDocument, table: &TrackedPaths, ids: &List<usize>): void {
    const bound = document.find_expression(span);
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
        if keyword(name) or property(bytes, start) {
            continue;
        }
        const kind = kind_by_name(script, name);
        if kind is none {
            continue;
        }
        if bound is expression_id {
            if not referenced(document, expression_id, name) {
                continue;
            }
        }
        var canonical = list<u8>();
        for byte in name.bytes() {
            canonical.push(byte);
        }
        var cursor = i;
        var segments: usize = 0;
        var scanning = true;
        while scanning {
            const dot = next_non_space(bytes, cursor);
            if dot is position {
                if bytes[position] != 46 {
                    scanning = false;
                } else {
                    var segment = position + 1;
                    while segment < bytes.len() and space(bytes[segment]) {
                        segment = segment + 1;
                    }
                    if segment >= bytes.len() {
                        scanning = false;
                    } else if not ident_start(bytes[segment]) {
                        scanning = false;
                    } else {
                        var end = segment + 1;
                        while end < bytes.len() and ident_continue(bytes[end]) {
                            end = end + 1;
                        }
                        var called = false;
                        if next_non_space(bytes, end) is call {
                            called = bytes[call] == 40;
                        }
                        if called {
                            scanning = false;
                        } else {
                            canonical.push(46);
                            for byte in bytes[segment..end] {
                                canonical.push(byte);
                            }
                            cursor = end;
                            segments = segments + 1;
                        }
                    }
                }
            } else {
                scanning = false;
            }
        }
        if segments > 0 {
            if kind is actual {
                append_unique(ids, ensure_chain(table, string.from(canonical.view()), name, actual));
            }
        }
    }
}
