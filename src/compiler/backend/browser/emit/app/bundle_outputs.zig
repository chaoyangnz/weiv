const std = @import("std");
const component_graph = @import("component_graph.zig");
const preview_props = @import("preview_props.zig");

pub fn emitBrowserEntry(allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator,
        \\import * as WeivApp from "./bundle.mjs";
        \\import {{ props as previewProps }} from "./props.mjs";
        \\
        \\const target = document.getElementById("app");
        \\const props = globalThis.__WEIV_PROPS__ ?? previewProps;
        \\
        \\if (target) {{
        \\  WeivApp.mount(target, props);
        \\}}
        \\
        \\export * from "./bundle.mjs";
        \\export default WeivApp;
        \\
    , .{});
}

pub fn emitDirectEntry(graph: *component_graph.ComponentGraph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    const root_import_path = try ensureRelativeSpecifier(graph.nodes.items[root_index].module_rel_path, allocator);
    defer allocator.free(root_import_path);
    try out.print(allocator, "import * as Root from \"{s}\";\n", .{root_import_path});

    var sorted = std.ArrayList(ComponentImport).empty;
    defer sorted.deinit(allocator);

    var iter = graph.component_registry.iterator();
    while (iter.next()) |entry| {
        try sorted.append(allocator, .{
            .tag_name = entry.key_ptr.*,
            .node_index = entry.value_ptr.*,
        });
    }

    std.mem.sort(ComponentImport, sorted.items, {}, compareComponentImport);

    for (sorted.items, 0..) |entry, idx| {
        const import_alias = try std.fmt.allocPrint(allocator, "Component_{d}", .{idx});
        defer allocator.free(import_alias);
        const import_path = try ensureRelativeSpecifier(graph.nodes.items[entry.node_index].module_rel_path, allocator);
        defer allocator.free(import_path);
        try out.print(allocator, "import * as {s} from \"{s}\";\n", .{ import_alias, import_path });
    }

    try out.appendSlice(allocator,
        \\
        \\export const components = {
        \\
    );
    for (sorted.items, 0..) |entry, idx| {
        try out.print(allocator, "  \"{s}\": Component_{d}", .{ entry.tag_name, idx });
        if (idx + 1 < sorted.items.len) {
            try out.appendSlice(allocator, ",\n");
        } else {
            try out.appendSlice(allocator, "\n");
        }
    }
    try out.appendSlice(allocator,
        \\};
        \\
        \\export const root = Root;
        \\export const cssPath = "./styles.css";
        \\
        \\export function mount(target, props = {}) {
        \\  return Root.mount(target, props);
        \\}
        \\
    );

    return try out.toOwnedSlice(allocator);
}

pub fn emitPropsModule(graph: *component_graph.ComponentGraph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
    const props_literal = try preview_props.inferLiteral(&graph.nodes.items[root_index].model, allocator);
    defer allocator.free(props_literal);

    return try std.fmt.allocPrint(allocator,
        \\export const props = {s};
        \\
    , .{props_literal});
}

pub fn emitIndexHtml(graph: *component_graph.ComponentGraph, root_index: usize, allocator: std.mem.Allocator) ![]u8 {
    const root_basename = std.fs.path.basename(graph.nodes.items[root_index].abs_path);
    const page_title = if (std.mem.endsWith(u8, root_basename, ".weiv"))
        root_basename[0 .. root_basename.len - ".weiv".len]
    else
        root_basename;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "<!doctype html>\n<html lang=\"en\">\n  <head>\n");
    try out.appendSlice(allocator, "    <meta charset=\"utf-8\" />\n");
    try out.appendSlice(allocator, "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n");
    try out.print(allocator, "    <title>{s}</title>\n", .{page_title});
    try out.appendSlice(allocator, "    <link rel=\"stylesheet\" href=\"/styles.css\" />\n");
    try out.appendSlice(allocator, "  </head>\n  <body>\n");
    try out.appendSlice(allocator, "    <div id=\"app\"></div>\n");
    try out.appendSlice(allocator, "    <script type=\"module\" src=\"/main.mjs\"></script>\n");
    try out.appendSlice(allocator, "  </body>\n</html>\n");

    return try out.toOwnedSlice(allocator);
}

pub fn emitPackageJson(allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "weiv-preview",
        \\  "private": true,
        \\  "type": "module",
        \\  "scripts": {{
        \\    "dev": "bun --hot server.ts",
        \\    "start": "bun server.ts"
        \\  }}
        \\}}
        \\
    , .{});
}

pub fn emitDevServer(allocator: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(allocator,
        \\const host = Bun.env.HOST ?? "0.0.0.0";
        \\const port = Number(Bun.env.PORT ?? 3000);
        \\const packagePrefix = "/__weiv_packages/";
        \\const packageBundles = new Map<string, Promise<Blob>>();
        \\
        \\function bundlePackage(specifier: string) {{
        \\  let pending = packageBundles.get(specifier);
        \\  if (!pending) {{
        \\    pending = (async () => {{
        \\      const entrypoint = Bun.resolveSync(specifier, import.meta.dir);
        \\      const result = await Bun.build({{ entrypoints: [entrypoint], target: "browser", format: "esm" }});
        \\      if (!result.success || result.outputs.length !== 1) {{
        \\        throw new Error(`Failed to bundle package ${{specifier}}`);
        \\      }}
        \\      return result.outputs[0];
        \\    }})();
        \\    packageBundles.set(specifier, pending);
        \\  }}
        \\  return pending;
        \\}}
        \\
        \\const server = Bun.serve({{
        \\  hostname: host,
        \\  port,
        \\  async fetch(req) {{
        \\    const url = new URL(req.url);
        \\    const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
        \\    if (pathname.startsWith(packagePrefix)) {{
        \\      const specifier = decodeURIComponent(pathname.slice(packagePrefix.length));
        \\      if (!specifier || specifier.startsWith(".") || specifier.includes("\\")) {{
        \\        return new Response("Invalid package specifier", {{ status: 400 }});
        \\      }}
        \\      try {{
        \\        return new Response(await bundlePackage(specifier), {{ headers: {{ "content-type": "text/javascript; charset=utf-8" }} }});
        \\      }} catch (error) {{
        \\        return new Response(String(error), {{ status: 404 }});
        \\      }}
        \\    }}
        \\    const staticFile = Bun.file(new URL(`.${{pathname}}`, import.meta.url));
        \\
        \\    if (await staticFile.exists()) {{
        \\      return new Response(staticFile);
        \\    }}
        \\
        \\    const fallbackFile = Bun.file(new URL("./index.html", import.meta.url));
        \\    if (await fallbackFile.exists()) {{
        \\      return new Response(fallbackFile);
        \\    }}
        \\
        \\    return new Response("Not Found", {{ status: 404 }});
        \\  }},
        \\}});
        \\
        \\console.log(`weiv preview server running at http://${{host}}:${{server.port}}`);
        \\
    , .{});
}

const ComponentImport = struct {
    tag_name: []const u8,
    node_index: usize,
};

fn compareComponentImport(_: void, a: ComponentImport, b: ComponentImport) bool {
    return std.mem.lessThan(u8, a.tag_name, b.tag_name);
}

fn ensureRelativeSpecifier(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (std.mem.startsWith(u8, path, "./") or std.mem.startsWith(u8, path, "../")) {
        return try allocator.dupe(u8, path);
    }
    return try std.fmt.allocPrint(allocator, "./{s}", .{path});
}
