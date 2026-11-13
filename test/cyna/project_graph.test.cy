import std.mem;
import { cwd } from std.process;
import { normalize, component, module_path } from .compiler.project.resolve_component_path;
import { collect } from .compiler.project.collect_component_graph;
import { build, ProjectBuildError } from .compiler.project.build_project;
import { ProjectBuild, ProjectModule } from .compiler.project.project_build;
import { relative_output } from .compiler.project.output_paths;
import { write, WriteError } from .compiler.project.write_project;
import { ProjectDiagnostic } from .compiler.project.diagnostics;
import std.fs;
import std.json;
import { format as inspect_project } from .compiler.project.inspect_project;

test "component paths normalize dot segments and retain relative module output" {
    const path = component("/project/src/App.weiv", "./cards/../Card.weiv") catch (code) {
        panic("Expected component path");
    };
    assert(path == "/project/src/Card.weiv");
    const output = module_path("/project", path) catch (code) {
        panic("Expected module output");
    };
    assert(output == "src/Card.mjs");
}

test "relative module outputs match browser import specifiers" {
    assert(relative_output("CardUsage.mjs", "Card.mjs") == "./Card.mjs");
    assert(relative_output("__weiv_modules/a.mjs", "__weiv_modules/b.mjs") == "./b.mjs");
    assert(relative_output("__weiv_modules/a.mjs", "__weiv_runtime/cell.js") == "../__weiv_runtime/cell.js");
    assert(relative_output("sub/a.mjs", "__weiv_modules/b.mjs") == "../__weiv_modules/b.mjs");
}

test "component graph discovers imported slot component from repository fixture" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/examples/slots";
    const entry = $"{root}/CardUsage.weiv";
    const graph = collect(root, entry) catch (code) {
        panic("Expected component graph");
    };
    assert(graph.nodes.len() == 2);
    assert(graph.imports.len() == 1);
    assert(graph.nodes[0].module_path == "CardUsage.mjs");
    assert(graph.nodes[1].module_path == "Card.mjs");
    assert(graph.imports[0].local_name == "Card");
    const project = build(&graph) catch (code) {
        panic("Expected project browser modules");
    };
    assert(project.modules.len() == 2);
    assert(project.entry_module == "CardUsage.mjs");
    const entry_module = &project.modules[0];
    const code = entry_module.code.bytes();
    assert(mem.contains(code, "./Card.mjs".bytes()));
}

test "project build includes relative JavaScript dependency" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/local-module";
    const entry = $"{root}/App.weiv";
    const graph = collect(root, entry) catch (code) {
        panic("Expected component graph");
    };
    assert(graph.nodes.len() == 1);
    const project = build(&graph) catch (code) {
        panic("Expected project build");
    };
    assert(project.modules.len() == 4);
    const dependency = &project.modules[1];
    const nested = &project.modules[2];
    const marker = &project.modules[3];
    assert(mem.starts_with(dependency.module_path.bytes(), "__weiv_modules/".bytes()));
    assert(mem.contains(dependency.code.bytes(), relative_output(dependency.module_path, nested.module_path).bytes()));
    assert(mem.contains(dependency.code.bytes(), relative_output(dependency.module_path, marker.module_path).bytes()));
    assert(mem.contains(nested.code.bytes(), relative_output(nested.module_path, dependency.module_path).bytes()));
    assert(mem.contains(nested.code.bytes(), "loaded".bytes()));
    assert(mem.starts_with(marker.module_path.bytes(), "__weiv_modules/".bytes()));
    assert(not mem.contains(marker.code.bytes(), ": string".bytes()));
}

test "project build emits local cell and imported observable fixture" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/examples/basic";
    const entry = $"{root}/compiler-cells-import.weiv";
    const graph = collect(root, entry) catch (code) {
        panic("Expected reactive component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected reactive browser project");
    };
    assert(project.modules.len() == 3);
    const component = &project.modules[0];
    assert(mem.contains(component.code.bytes(), "__weiv_cellScope.watch(count, \"count\");".bytes()));
    assert(mem.contains(component.code.bytes(), "__weiv_cellScope.watch(__weiv_publisher_0.getCell(\"shared\"), \"shared\");".bytes()));
    const state = &project.modules[1];
    assert(mem.starts_with(state.module_path.bytes(), "__weiv_modules/".bytes()));
    assert(mem.ends_with(state.module_path.bytes(), ".mjs".bytes()));
    const publisher = &project.modules[2];
    const state_path = state.module_path.bytes();
    const publisher_prefix = string.from(state_path[..state_path.len() - 4]);
    assert(publisher.module_path == $"{publisher_prefix}.publisher.mjs");
}

test "project build transpiles transitive TypeScript modules" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/examples/imported-ts-helper";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected TypeScript component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected transpiled helper graph");
    };
    assert(project.modules.len() == 3);
    const helper = &project.modules[1];
    const punctuation = &project.modules[2];
    assert(mem.starts_with(helper.module_path.bytes(), "__weiv_modules/".bytes()));
    assert(mem.starts_with(punctuation.module_path.bytes(), "__weiv_modules/".bytes()));
    assert(helper.module_path != punctuation.module_path);
    assert(mem.contains(helper.code.bytes(), relative_output(helper.module_path, punctuation.module_path).bytes()));
    assert(not mem.contains(helper.code.bytes(), "value: string".bytes()));
    assert(mem.contains(punctuation.code.bytes(), "suffix".bytes()));
}

test "project inspector emits valid module graph JSON" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/examples/slots";
    const graph = collect(root, $"{root}/CardUsage.weiv") catch (code) {
        panic("Expected project graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected project build");
    };
    const encoded = inspect_project(&graph, &project);
    const value = json.parse(encoded) catch (code) {
        panic("Expected valid project inspection JSON");
    };
    switch value {
        .object(object) => {
            assert(object.contains("entry"));
            assert(object.contains("components"));
            assert(object.contains("componentImports"));
            assert(object.contains("modules"));
            assert(object.contains("stylesheetBytes"));
        }
        _ => {
            panic("Expected project inspection object");
        }
    }
    assert(mem.contains(encoded.bytes(), "\"CardUsage.mjs\"".bytes()));
    assert(mem.contains(encoded.bytes(), "\"Card.mjs\"".bytes()));
}

test "project build selects direct mutable managed publisher" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/managed-state";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected managed component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected managed project");
    };
    assert(project.modules.len() == 3);
    const component = &project.modules[0];
    assert(mem.contains(component.code.bytes(), "__weiv_publisher_0.getCell(\"count\")".bytes()));
    assert(mem.contains(component.code.bytes(), "__weiv_publisher_1.getCell(\"other\")".bytes()));
    const state = &project.modules[1];
    assert(mem.contains(state.code.bytes(), "__weiv_afterModuleWrite".bytes()));
    const publisher = &project.modules[2];
    assert(mem.starts_with(state.module_path.bytes(), "__weiv_modules/".bytes()));
    const state_path = state.module_path.bytes();
    const publisher_prefix = string.from(state_path[..state_path.len() - 4]);
    assert(publisher.module_path == $"{publisher_prefix}.publisher.mjs");
    assert(mem.contains(component.code.bytes(), relative_output(component.module_path, publisher.module_path).bytes()));
    assert(mem.contains(publisher.code.bytes(), "createModuleState".bytes()));
}

test "project build follows local export and import aliases for managed state" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/managed-alias";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected aliased component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected aliased managed project");
    };
    assert(project.modules.len() == 3);
    const component = &project.modules[0];
    assert(mem.contains(component.code.bytes(), "getCell(\"count\")".bytes()));
    const publisher = &project.modules[2];
    assert(mem.ends_with(publisher.module_path.bytes(), ".publisher.mjs".bytes()));
    assert(mem.contains(component.code.bytes(), relative_output(component.module_path, publisher.module_path).bytes()));
}

test "project build resolves named reexport chain to owning publisher module" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/managed-reexport";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected reexport component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected reexport managed project");
    };
    assert(project.modules.len() == 5);
    const component = &project.modules[0];
    const publisher = &project.modules[4];
    assert(mem.contains(component.code.bytes(), relative_output(component.module_path, publisher.module_path).bytes()));
    assert(mem.contains(component.code.bytes(), "getCell(\"count\")".bytes()));
    assert(mem.ends_with(publisher.module_path.bytes(), ".publisher.mjs".bytes()));
}

test "project build resolves star reexport to owning publisher module" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/managed-star";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected star reexport component graph");
    };
    const project = build(&graph) catch (code) {
        panic("Expected star reexport managed project");
    };
    assert(project.modules.len() == 4);
    const component = &project.modules[0];
    const publisher = &project.modules[3];
    assert(mem.contains(component.code.bytes(), relative_output(component.module_path, publisher.module_path).bytes()));
    assert(mem.contains(component.code.bytes(), "getCell(\"count\")".bytes()));
    assert(mem.ends_with(publisher.module_path.bytes(), ".publisher.mjs".bytes()));
}

test "project build rejects ambiguous managed star export" {
    const directory = cwd() catch (code) {
        panic("Expected current directory");
    };
    const root = $"{directory}/test/fixtures/cyna/managed-star-ambiguous";
    const graph = collect(root, $"{root}/App.weiv") catch (code) {
        panic("Expected ambiguous component graph");
    };
    const _ = build(&graph) catch (code) {
        assert(code == ProjectBuildError.ambiguous_managed_export);
        return;
    };
    panic("Expected ambiguous managed export failure");
}

test "project writer rejects escaping artifact before creating output" {
    const output = "/tmp/weiv-cyna-invalid-writer-20261108";
    const absent = fs.exists(output) catch (code) {
        panic("Expected filesystem query");
    };
    assert(not absent);
    var modules = list<ProjectModule>();
    modules.push(ProjectModule {
        source_path: "/project/App.weiv",
        module_path: "../outside.mjs",
        code: "unsafe",
        css: ""
    });
    const project = ProjectBuild {
        entry_module: "App.mjs",
        modules: modules,
        stylesheet: "",
        diagnostics: list<ProjectDiagnostic>()
    };
    var rejected = false;
    write(&project, output) catch (code) {
        rejected = code == WriteError.invalid_path;
    };
    assert(rejected);
    const created = fs.exists(output) catch (code) {
        panic("Expected filesystem query");
    };
    assert(not created);
}
