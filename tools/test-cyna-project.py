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
        "cyna", "run", "cyna-port", "--", "--runtime-dir", str(RUNTIME_DIST),
        "emit", "app", entry, str(output),
    )


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
    emit_app("cyna-port/fixtures/local-module/App.weiv", nested_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in nested_output.iterdir()}
    )
    marker_code = (nested_output / "__weiv_modules/7777f37e492788be.mjs").read_text()
    assert 'from "../__weiv_runtime/observable.js"' in marker_code
    assert '"weiv:cells"' in marker_code
    assert 'from "./888eff0220692a5.mjs"' in marker_code
    assert (nested_output / "__weiv_modules/888eff0220692a5.mjs").exists()
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
    emit_app("cyna-port/fixtures/managed-state/App.weiv", managed_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in managed_output.iterdir()}
    )
    managed_harness = managed_output / "runtime.mjs"
    managed_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {count, other} from "./__weiv_modules/37a574638e2a0b9.mjs";
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
''')
    run("bun", str(managed_harness))

    alias_output = output / "managed-alias-project"
    emit_app("cyna-port/fixtures/managed-alias/App.weiv", alias_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in alias_output.iterdir()}
    )
    alias_harness = alias_output / "runtime.mjs"
    alias_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {shown} from "./__weiv_modules/4b5e25a670df9da2.mjs";
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
''')
    run("bun", str(alias_harness))

    reexport_output = output / "managed-reexport-project"
    emit_app("cyna-port/fixtures/managed-reexport/App.weiv", reexport_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in reexport_output.iterdir()}
    )
    assert (reexport_output / "__weiv_modules/e7696116c4077457.mjs").exists()
    assert (reexport_output / "__weiv_modules/19d67629b129cde1.publisher.mjs").exists()
    reexport_harness = reexport_output / "runtime.mjs"
    reexport_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {shown} from "./__weiv_modules/cec8d44aeecbb671.mjs";
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
''')
    run("bun", str(reexport_harness))

    star_output = output / "managed-star-project"
    emit_app("cyna-port/fixtures/managed-star/App.weiv", star_output)
    assert {"App.mjs", "__weiv_modules", "styles.css", "__weiv_runtime"}.issubset(
        {path.name for path in star_output.iterdir()}
    )
    assert (star_output / "__weiv_modules/64d771279ac37ef9.publisher.mjs").exists()
    star_harness = star_output / "runtime.mjs"
    star_harness.write_text('''import assert from "node:assert/strict";
import {JSDOM} from "jsdom";
import * as App from "./App.mjs";
import {count} from "./__weiv_modules/3516a6ff2938a45f.mjs";
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
''')
    run("bun", str(star_harness))
