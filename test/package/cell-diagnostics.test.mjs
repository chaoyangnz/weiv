import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const binary = process.env.WEIV_BINARY_PATH || join(root, "zig-out/bin/weiv");
const temp = mkdtempSync(join(tmpdir(), "weiv-cell-diagnostics-"));
function run(...args) {
  return spawnSync(binary, args, { cwd: root, encoding: "utf8" });
}
function verify(entry, source, path, expression, code, occurrence = 0) {
  assert.equal(entry.code, code);
  assert.equal(entry.severity, "error");
  assert.equal(entry.stage, "emit");
  assert.equal(entry.fatal, true);
  assert.equal(entry.sourcePath, path);
  let start = -1;
  for (let index = 0; index <= occurrence; index++) start = source.indexOf(expression, start + 1);
  assert(start >= 0);
  assert.deepEqual(entry.span, { start: Buffer.byteLength(source.slice(0, start)), end: Buffer.byteLength(source.slice(0, start + expression.length)) });
  const before = source.slice(0, start).split("\n");
  assert.deepEqual(entry.location, { line: before.length, column: Buffer.byteLength(before.at(-1)) + 1 });
  assert(entry.message.length > 50, entry.message);
}
try {
  writeFileSync(join(temp, "source.ts"), "export let imported=0;");
  const cases = [
    ['<p>{{ count++ }}</p>', 'let count=0;', 'count++', 'reactivity.render_mutation', 'event handler'],
    ['<button @click="count++">go</button>', 'const count=0;', 'count++', 'reactivity.readonly_assignment', 'let'],
    ['<button @click="imported++">go</button>', "import {imported} from './source.ts';", 'imported++', 'reactivity.readonly_assignment', 'mutation function'],
    ['<button #for="row in rows" @click="row++">go</button>', 'const rows=[1];', 'row++', 'reactivity.readonly_assignment', 'loop alias'],
    ['<button @click="read=()=>1">go</button>', 'function read(){return 0}', 'read=()=>1', 'reactivity.untracked_assignment', 'let binding'],
    ['<button @click="eval(\'count++\')">go</button>', 'let count=0;', "eval('count++')", 'reactivity.dynamic_eval', 'statically defined'],
    ['<p #if="count++">go</p>', 'let count=0;', 'count++', 'reactivity.render_mutation', 'event handler'],
    ['<button :title="count++">go</button>', 'let count=0;', 'count++', 'reactivity.render_mutation', 'event handler'],
    ['<button #for="row in (count++,rows)">go</button>', 'let count=0;const rows=[1];', '(count++,rows)', 'reactivity.render_mutation', 'event handler'],
    ['<section #for="row in rows"><button #for="row in row.children" @click="row++">go</button></section>', 'const rows=[{children:[1]}];', 'row++', 'reactivity.readonly_assignment', 'loop alias'],
  ];
  for (const [template, script, expression, code, action] of cases) {
    const path = join(temp, "Failure.weiv");
    const source = `<template>\n  ${template}\n</template>\n<script lang="ts">\n${script}\n</script>`;
    writeFileSync(path, source);
    const result = run("--json-diagnostics", "emit", "js", path);
    assert.notEqual(result.status, 0, result.stderr);
    assert.equal(result.stdout, "");
    const report = JSON.parse(result.stderr);
    assert.equal(report.ok, false);
    assert.equal(report.diagnostics.length, 1, result.stderr);
    verify(report.diagnostics[0], source, path, expression, code);
    assert(report.diagnostics[0].message.includes(action), result.stderr);
  }

  // Identical source text has different meaning in its original lexical scope.
  const path = join(temp, "Repeated.weiv");
  const source = `<template>\n<button @click="count++">valid</button>\n<p>{{ count++ }}</p>\n<p>{{ count++ }}</p>\n</template>\n<script lang="ts">let count=0;</script>`;
  writeFileSync(path, source);
  const repeated = run("--json-diagnostics", "emit", "js", path);
  assert.notEqual(repeated.status, 0);
  const repeatedReport = JSON.parse(repeated.stderr);
  assert.equal(repeatedReport.diagnostics.length, 2, repeated.stderr);
  repeatedReport.diagnostics.forEach((entry, index) => verify(entry, source, path, "count++", "reactivity.render_mutation", index + 1));
  const text = run("emit", "js", path);
  assert.notEqual(text.status, 0);
  assert(text.stderr.includes("[3:7]"), text.stderr);
  assert(text.stderr.includes("Move this write into an event handler"), text.stderr);


  // An invalid script must not be falsely attributed to its valid template read.
  const invalidScript = join(temp, "Script.weiv");
  const scriptSource = '<template><p>{{ count }}</p></template><script lang="ts">const count=0; count++;</script>';
  writeFileSync(invalidScript, scriptSource);
  const scriptFailure = run("--json-diagnostics", "emit", "js", invalidScript);
  assert.notEqual(scriptFailure.status, 0);
  const scriptReport = JSON.parse(scriptFailure.stderr);
  assert.equal(scriptReport.diagnostics.length, 1);
  verify(scriptReport.diagnostics[0], scriptSource, invalidScript, "count", "reactivity.readonly_assignment", 2);

  for (const [script, selected, code, snippet, occurrence, action] of [
    ['var count=0;', 'count', 'reactivity.unsupported_declaration', 'var count=0;', 0, 'let or const'],
    ['var {count}={count:0};', 'count', 'reactivity.unsupported_declaration', 'var {count}={count:0};', 0, 'let or const'],
    ['declare let count:number;', 'count', 'reactivity.ambient_declaration', 'declare let count:number;', 0, 'real initializer'],
    ['let count=0; eval("count++");', 'count', 'reactivity.dynamic_eval', 'eval', 0, 'statically defined'],
    ['let count=await Promise.resolve(1);', 'count', 'reactivity.unsupported_await', 'await Promise.resolve(1)', 0, 'async helper'],
    ['const {count=class {static label=this.name}}={};function shadow(count){count++}count++;', 'count', 'reactivity.readonly_assignment', 'count', 4, 'let'],
    ['let __weiv_count=0;', '__weiv_count', 'reactivity.reserved_identifier', '__weiv_count', 1, 'Rename'],
    ['let count=0;export default count;', 'count', 'reactivity.component_default_export', 'export default count;', 0, 'Remove'],
  ]) {
    const source = `<template><p>{{ ${selected} }}</p></template>\n<script lang="ts">\n// λ makes byte offsets differ from character offsets\n${script}\n</script>`;
    writeFileSync(invalidScript, source);
    const failure = run('--json-diagnostics', 'emit', 'js', invalidScript);
    assert.notEqual(failure.status, 0, source);
    const report = JSON.parse(failure.stderr);
    assert.equal(report.diagnostics.length, 1, failure.stderr);
    verify(report.diagnostics[0], source, invalidScript, snippet, code, occurrence);
    assert(report.diagnostics[0].message.includes(action), failure.stderr);
  }

  // Managed builds identify the child source, rather than the application root.
  const child = join(temp, "Child.weiv");
  const childSource = '<template>\n<button @click="count++">go</button>\n</template><script lang="ts">const count=0;</script>';
  writeFileSync(child, childSource);
  const parent = join(temp, "Parent.weiv");
  writeFileSync(parent, '<template><Child /></template><script lang="ts">import Child from "./Child.weiv";</script>');
  for (const prefix of [["emit"], ["compile", "emit"]]) {
    const app = run("--json-diagnostics", ...prefix, "app", parent, join(temp, "out"));
    assert.notEqual(app.status, 0);
    const report = JSON.parse(app.stderr); // Exactly one structured report.
    const errors = report.diagnostics.filter(entry => entry.fatal);
    assert.equal(errors.length, 1, app.stderr);
    verify(errors[0], childSource, realpathSync(child), "count++", "reactivity.readonly_assignment");
  }

  const modulePath = join(temp, 'Shared.ts');
  const moduleSource = '// λ and type erasure shift generated offsets\nexport type State={n:number};\nexport var count:State={n:0};';
  writeFileSync(modulePath, moduleSource);
  const moduleFailure = run('--json-diagnostics', 'emit', 'module-cells', modulePath, './publisher.mjs', '["count"]');
  assert.notEqual(moduleFailure.status, 0);
  const moduleReport = JSON.parse(moduleFailure.stderr);
  assert.equal(moduleReport.diagnostics.length, 1, moduleFailure.stderr);
  verify(moduleReport.diagnostics[0], moduleSource, modulePath, 'var count:State={n:0};', 'reactivity.unsupported_declaration');
  const sharedParent = join(temp, 'SharedParent.weiv');
  writeFileSync(sharedParent, '<template><p>{{ count.n }}</p></template><script lang="ts">import {count} from "./Shared.ts";</script>');
  const unsupportedManaged = run('--json-diagnostics', 'emit', 'app', sharedParent, join(temp, 'var-output'));
  assert.equal(unsupportedManaged.status, 0, unsupportedManaged.stderr);
  assert(JSON.parse(unsupportedManaged.stderr).diagnostics.some(entry => entry.code === 'reactivity.untracked_external_state' && !entry.fatal));
  const managedSource = '// λ and type erasure shift generated offsets\nexport type State={n:number};\nexport const count:State={n:0};\nexport function replace(){count={n:1};}';
  writeFileSync(modulePath, managedSource);
  const managedFailure = run('--json-diagnostics', 'emit', 'app', sharedParent, join(temp, 'shared-output'));
  assert.notEqual(managedFailure.status, 0);
  const managedReport = JSON.parse(managedFailure.stderr);
  const managedErrors = managedReport.diagnostics.filter(entry => entry.fatal);
  assert.equal(managedErrors.length, 1, managedFailure.stderr);
  verify(managedErrors[0], managedSource, realpathSync(modulePath), 'count', 'reactivity.readonly_assignment', 1);

  const awaitSource = 'export let {count=await Promise.resolve(1)}={};';
  writeFileSync(modulePath, awaitSource);
  const awaitFailure = run('--json-diagnostics', 'emit', 'module-cells', modulePath, './publisher.mjs', '["count"]');
  assert.notEqual(awaitFailure.status, 0);
  const awaitReport = JSON.parse(awaitFailure.stderr);
  verify(awaitReport.diagnostics[0], awaitSource, modulePath, 'await Promise.resolve(1)', 'reactivity.unsupported_await');
  const syntaxSource = '// λ\nexport let count=;';
  writeFileSync(modulePath, syntaxSource);
  const syntaxFailure = run('--json-diagnostics', 'emit', 'module-cells', modulePath, './publisher.mjs', '["count"]');
  assert.notEqual(syntaxFailure.status, 0);
  const syntaxReport = JSON.parse(syntaxFailure.stderr);
  verify(syntaxReport.diagnostics[0], syntaxSource, modulePath, ';', 'script.syntax');
  assert(syntaxReport.diagnostics[0].message.includes('Unexpected token'));
  const opaqueSource = '// λ\nexport const label="fixed";\nexport function load(name:string){return import(name)}';
  writeFileSync(modulePath, opaqueSource);
  writeFileSync(sharedParent, '<template><p>{{ label }}</p></template><script lang="ts">import {label} from "./Shared.ts";</script>');
  const opaqueFailure = run('--json-diagnostics', 'emit', 'app', sharedParent, join(temp, 'opaque-output'));
  assert.notEqual(opaqueFailure.status, 0);
  const opaqueReport = JSON.parse(opaqueFailure.stderr);
  const opaqueErrors = opaqueReport.diagnostics.filter(entry => entry.fatal);
  assert.equal(opaqueErrors.length, 1, opaqueFailure.stderr);
  verify(opaqueErrors[0], opaqueSource, realpathSync(modulePath), 'import(name)', 'reactivity.dynamic_module_import');
  assert(opaqueErrors[0].message.includes('literal module specifier'));
  for (const source of [
    '<template><p>{{ count }}</p></template><script lang="ts">let count=0;function load(name:string){return import(name)}</script>',
    '<template><button @click="import(event.detail.name)">load</button></template><script lang="ts">let count=0;</script>',
    '<template><p>{{ import(name) }}</p></template><script lang="ts">const name="./Shared.ts";</script>',
    '<template><p>{{ count }}</p></template><script lang="ts">let count=0;function load(){return import("./Shared.ts")}</script>',
    '<template><button @click="import(\'./Shared.ts\')">load</button></template><script lang="ts">let count=0;</script>',
    '<template><p>{{ import("./Shared.ts") }}</p></template><script lang="ts">let count=0;</script>',
  ]) {
    writeFileSync(sharedParent, source);
    const failure = run('--json-diagnostics', 'emit', 'app', sharedParent, join(temp, 'opaque-component'));
    assert.notEqual(failure.status, 0);
    const report = JSON.parse(failure.stderr);
    const errors = report.diagnostics.filter(entry => entry.fatal);
    assert.equal(errors.length, 1, failure.stderr);
    const expression = source.includes("import('./Shared.ts')") ? "'./Shared.ts'" : source.includes('import("./Shared.ts")') ? '"./Shared.ts"' : source.includes('event.detail.name') ? 'import(event.detail.name)' : 'import(name)';
    verify(errors[0], source, realpathSync(sharedParent), expression, 'reactivity.dynamic_module_import');
    assert(errors[0].message.includes('outside experimental managed loading'));
  }
  console.log("Cell diagnostics retain original script/template ranges, lexical scopes, guidance and managed child/shared-module paths");
} finally {
  rmSync(temp, { recursive: true, force: true });
}
