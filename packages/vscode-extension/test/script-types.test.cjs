const assert = require("node:assert/strict");
const { test } = require("node:test");
const { createVirtualScript, helperDiagnostics } = require("../out/script-types.js");

test("virtual helper types validate event names and payloads", () => {
  const file = "/tmp/Example.weiv";
  const source = `export interface Emits { save: number; close: void }
function run() {
  emit("save", 2);
  emit("close");
  emit("save", "bad");
  emit("close", 1);
}`;
  const virtual = createVirtualScript(file, source);
  try {
    assert.equal(helperDiagnostics(virtual, file).length, 2);
    const position = virtual.offset + source.indexOf('emit("save", 2)') + 7;
    assert.ok(virtual.service.getSignatureHelpItems(file + ".ts", position, undefined));
  } finally {
    virtual.service.dispose();
  }
});

test("emit stays usable without an Emits interface", () => {
  const file = "/tmp/Untyped.weiv";
  const virtual = createVirtualScript(file, 'emit("changed", 1);');
  try {
    assert.deepEqual(helperDiagnostics(virtual, file), []);
  } finally {
    virtual.service.dispose();
  }
});
