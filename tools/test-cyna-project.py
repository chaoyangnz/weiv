"""Exercise the Cyna project CLI output with imported components in Bun/jsdom."""

from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIST = ROOT / "packages/weiv/dist/runtime"


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True)


def emit_app(entry: str, output: Path) -> None:
    run(
        str(ROOT / "cyna-out/bin/weiv"), "--runtime-dir", str(RUNTIME_DIST),
        "emit", "app", entry, str(output),
    )


def find_module(output: Path, content: str) -> Path:
    matches = [path for path in (output / "__weiv_modules").glob("*.mjs") if content in path.read_text()]
    assert len(matches) == 1, (content, matches)
    return matches[0]


def module_import(output: Path, content: str) -> str:
    return f'./__weiv_modules/{find_module(output, content).name}'


with TemporaryDirectory(prefix=".cyna-project-", dir=ROOT) as directory:
    output = Path(directory)
    emit_app("test/examples/slots/CardUsage.weiv", output)
    assert {
        "CardUsage.mjs", "Card.mjs", "styles.css", "__weiv_runtime"
    }.issubset({path.name for path in output.iterdir()})
    assert {
        "bundle.mjs", "main.mjs", "props.mjs", "index.html", "package.json", "server.ts"
    }.issubset({path.name for path in output.iterdir()})
    harness = output / "runtime.mjs"
    harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./CardUsage.mjs";

const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root, {title:"First", eyebrow:"Eyebrow", body:"Body"});
assert.equal(root.querySelector("h2")?.textContent, "First");
assert.equal(root.querySelector(".card-usage__eyebrow")?.textContent, "Eyebrow");
assert.equal(root.querySelector(".card-usage__body")?.textContent, "Body");
handle.setProps({title:"Next", eyebrow:"Changed", body:"Updated"});
handle.update();
assert.equal(root.querySelector("h2")?.textContent, "Next");
assert.equal(root.querySelector(".card-usage__body")?.textContent, "Updated");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna project component and slots runtime passed");
''')
    run("bun", str(harness))

    nested_output = output / "nested-project"
    emit_app("test/fixtures/cyna/local-module/App.weiv", nested_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in nested_output.iterdir()}
    )
    marker_code = find_module(nested_output, 'from "../__weiv_runtime/observable.js"').read_text()
    assert 'from "../__weiv_runtime/observable.js"' in marker_code
    assert '"weiv:cells"' in marker_code
    assert 'from "./' in marker_code
    nested_harness = nested_output / "runtime.mjs"
    nested_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root, {title:"Imported"});
assert.equal(root.textContent, "Imported");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna transitive JavaScript module graph passed");
''')
    run("bun", str(nested_harness))

    reactive_output = output / "reactive-project"
    emit_app("test/examples/basic/compiler-cells-import.weiv", reactive_output)
    assert {"compiler-cells-import.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in reactive_output.iterdir()}
    )
    reactive_harness = reactive_output / "runtime.mjs"
    reactive_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./compiler-cells-import.mjs";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root);
assert.equal(root.textContent, "0 / 0");
window.dispatchEvent(new dom.window.Event("cells-mixed"));
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(root.textContent, "1 / 1");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna imported observable and local cell runtime passed");
''')
    run("bun", str(reactive_harness))

    typescript_output = output / "typescript-project"
    emit_app("test/examples/imported-ts-helper/App.weiv", typescript_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in typescript_output.iterdir()}
    )
    typescript_harness = typescript_output / "runtime.mjs"
    typescript_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root, {title:"World", count:2});
assert.equal(root.querySelector("h1")?.textContent, "TS hello, World!");
assert.equal(root.querySelector("p")?.textContent, "2");
handle.setProps({title:"Cyna", count:3});
handle.update();
assert.equal(root.querySelector("h1")?.textContent, "TS hello, Cyna!");
assert.equal(root.querySelector("p")?.textContent, "3");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna transitive TypeScript module graph passed");
''')
    run("bun", str(typescript_harness))

    managed_output = output / "managed-project"
    emit_app("test/fixtures/cyna/managed-state/App.weiv", managed_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in managed_output.iterdir()}
    )
    managed_harness = managed_output / "runtime.mjs"
    managed_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {count, other} from "STATE_MODULE";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root);
assert.equal(root.querySelector("p")?.textContent, "0 / 0");
root.querySelector("button").dispatchEvent(new dom.window.Event("click"));
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(count, 1);
assert.equal(other, 1);
assert.equal(root.querySelector("p")?.textContent, "1 / 1");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna direct managed publisher runtime passed");
'''.replace("STATE_MODULE", module_import(managed_output, "export let count")))
    run("bun", str(managed_harness))

    alias_output = output / "managed-alias-project"
    emit_app("test/fixtures/cyna/managed-alias/App.weiv", alias_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in alias_output.iterdir()}
    )
    alias_harness = alias_output / "runtime.mjs"
    alias_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {shown} from "ALIAS_MODULE";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root);
assert.equal(root.querySelector("p")?.textContent, "0");
root.querySelector("button").dispatchEvent(new dom.window.Event("click"));
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(shown, 1);
assert.equal(root.querySelector("p")?.textContent, "1");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna managed export and import aliases passed");
'''.replace("ALIAS_MODULE", module_import(alias_output, "export { count as shown }")))
    run("bun", str(alias_harness))

    reexport_output = output / "managed-reexport-project"
    emit_app("test/fixtures/cyna/managed-reexport/App.weiv", reexport_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in reexport_output.iterdir()}
    )
    assert find_module(reexport_output, "export { count as shown").exists()
    assert find_module(reexport_output, "createModuleState").exists()
    reexport_harness = reexport_output / "runtime.mjs"
    reexport_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {shown} from "REEXPORT_MODULE";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root);
assert.equal(root.querySelector("p")?.textContent, "0");
root.querySelector("button").dispatchEvent(new dom.window.Event("click"));
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(shown, 1);
assert.equal(root.querySelector("p")?.textContent, "1");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna managed named reexport runtime passed");
'''.replace("REEXPORT_MODULE", module_import(reexport_output, "export { count as shown")))
    run("bun", str(reexport_harness))

    star_output = output / "managed-star-project"
    emit_app("test/fixtures/cyna/managed-star/App.weiv", star_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in star_output.iterdir()}
    )
    assert find_module(star_output, "createModuleState").exists()
    star_harness = star_output / "runtime.mjs"
    star_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {count} from "STAR_MODULE";
const dom = new JSDOM("<main></main>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const root = document.querySelector("main");
const handle = App.mount(root);
assert.equal(root.querySelector("p")?.textContent, "0");
root.querySelector("button").dispatchEvent(new dom.window.Event("click"));
await new Promise(resolve => setTimeout(resolve, 0));
assert.equal(count, 1);
assert.equal(root.querySelector("p")?.textContent, "1");
handle.destroy();
assert.equal(root.textContent, "");
console.log("Cyna managed star reexport runtime passed");
'''.replace("STAR_MODULE", module_import(star_output, "export let count")))
    run("bun", str(star_harness))
