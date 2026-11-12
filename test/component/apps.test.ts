import { test } from "bun:test";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  FakeDocument,
  FakeTextNode,
  byClass,
  byTag,
  byTagAndClass,
  change,
  click,
  dblclick,
  emitApp,
  emitDirectBrowserModule,
  findElement,
  findElements,
  importModule,
  installDocument,
  installRouterWindow,
  keydown,
  loadModules,
} from "./support";

function managedModules(directory: string) {
  const modules = join(directory, "__weiv_modules");
  return readdirSync(modules)
    .filter(name => name.endsWith(".mjs") && !name.endsWith(".publisher.mjs"))
    .map(name => readFileSync(join(modules, name), "utf8"))
    .join("\n");
}

test("classic app emits and helper-copy flows stay healthy", async () => {
  const bundleDir = mkdtempSync(join(tmpdir(), "weiv-app-emit-"));
  try {
    emitApp("test/examples/classic-todo/App.weiv", bundleDir);
    const indexHtml = readFileSync(join(bundleDir, "index.html"), "utf8");
    const browserEntry = readFileSync(join(bundleDir, "main.mjs"), "utf8");
    const propsModule = readFileSync(join(bundleDir, "props.mjs"), "utf8");
    const packageJson = readFileSync(join(bundleDir, "package.json"), "utf8");
    const devServer = readFileSync(join(bundleDir, "server.ts"), "utf8");
    if (!indexHtml.includes('<script type="module" src="/main.mjs"></script>')) {
      throw new Error("Bundled index.html missing browser module entry");
    }
    if (
      !browserEntry.includes('import { props as previewProps } from "./props.mjs";') ||
      !browserEntry.includes("const props = globalThis.__WEIV_PROPS__ ?? previewProps;") ||
      !browserEntry.includes("WeivApp.mount(target, props);")
    ) {
      throw new Error("Bundled main.mjs missing browser render bootstrap");
    }
    if (!propsModule.includes('export const props = { title: "Preview" };')) {
      throw new Error("Bundled props.mjs missing preview props");
    }
    if (
      !packageJson.includes('"dev": "bun --hot server.ts"') ||
      !packageJson.includes('"start": "bun server.ts"')
    ) {
      throw new Error("Bundled package.json missing Bun preview scripts");
    }
    if (
      !devServer.includes("const server = Bun.serve({") ||
      !devServer.includes('pathname === "/" ? "/index.html"') ||
      !devServer.includes('new URL("./index.html", import.meta.url)')
    ) {
      throw new Error("Bundled server.ts missing static Bun server bootstrap");
    }
    const bundleModule = await importModule(join(bundleDir, "bundle.mjs"));
    const bundledStyles = readFileSync(join(bundleDir, "styles.css"), "utf8");
    if (
      !bundledStyles.includes(".todo-app") ||
      !bundledStyles.includes(".todo-list") ||
      !bundledStyles.includes(".todo-item")
    ) {
      throw new Error("Bundled styles missing expected selectors");
    }
    if (typeof bundleModule.mount !== "function") {
      throw new Error("Classic todo bundle missing mount export");
    }
    if (
      !bundleModule.root?.scopeId ||
      !bundleModule.components?.TodoList?.scopeId ||
      !bundleModule.components?.TodoItem?.scopeId
    ) {
      throw new Error("Classic todo bundle missing scoped component metadata");
    }
  } finally {
    rmSync(bundleDir, { recursive: true, force: true });
  }

  const counterBundleDir = mkdtempSync(join(tmpdir(), "weiv-counter-bundle-"));
  try {
    emitApp("test/examples/basic/basic-counter.weiv", counterBundleDir);
    const counterProps = readFileSync(join(counterBundleDir, "props.mjs"), "utf8");
    if (!counterProps.includes('title: "Preview"') || !counterProps.includes("initialCount: 0")) {
      throw new Error("BasicCounter bundled props.mjs missing inferred preview props");
    }
  } finally {
    rmSync(counterBundleDir, { recursive: true, force: true });
  }

  const importedHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-helper-bundle-"));
  try {
    emitApp("test/examples/imported-helper/App.weiv", importedHelperBundleDir);
    const helperModule = managedModules(importedHelperBundleDir);
    const punctuationModule = managedModules(importedHelperBundleDir);
    const helperAppModule = readFileSync(join(importedHelperBundleDir, "App.mjs"), "utf8");
    const helperProps = readFileSync(join(importedHelperBundleDir, "props.mjs"), "utf8");
    if (!helperModule.includes("export function formatTitle")) {
      throw new Error("Imported helper bundle missing copied format.js");
    }
    if (!helperModule.includes('import { suffix } from "./')) {
      throw new Error("Imported helper bundle missing transitive helper import");
    }
    if (!punctuationModule.includes("export const suffix =")) {
      throw new Error("Imported helper bundle missing copied punctuation.js");
    }
    if (
      !helperAppModule.includes('import { formatTitle as __weiv_import_formatTitle } from "./__weiv_modules/')
    ) {
      throw new Error("Imported helper bundle missing preserved runtime import");
    }
    if (!helperProps.includes('title: "Preview"') || !helperProps.includes("count: 0")) {
      throw new Error("Imported helper bundle missing inferred preview props");
    }

    const importedHelperBundle = await importModule(join(importedHelperBundleDir, "bundle.mjs"));
    if (typeof importedHelperBundle.mount !== "function" || !importedHelperBundle.root?.scopeId) {
      throw new Error("Imported helper bundle missing direct bundle contract");
    }
  } finally {
    rmSync(importedHelperBundleDir, { recursive: true, force: true });
  }

  const importedTsHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-ts-helper-bundle-"));
  try {
    emitApp("test/examples/imported-ts-helper/App.weiv", importedTsHelperBundleDir);
    const tsHelperModule = managedModules(importedTsHelperBundleDir);
    const tsPunctuationModule = managedModules(importedTsHelperBundleDir);
    const tsHelperAppModule = readFileSync(join(importedTsHelperBundleDir, "App.mjs"), "utf8");
    const tsHelperProps = readFileSync(join(importedTsHelperBundleDir, "props.mjs"), "utf8");
    if (!tsHelperModule.includes('import { suffix } from "./')) {
      throw new Error("Imported TS helper bundle missing rewritten transitive helper import");
    }
    if (!tsPunctuationModule.includes("export const suffix =")) {
      throw new Error("Imported TS helper bundle missing transpiled punctuation.js");
    }
    if (
      !tsHelperAppModule.includes(
        'import { formatTitle as __weiv_import_formatTitle } from "./__weiv_modules/',
      )
    ) {
      throw new Error("Imported TS helper bundle missing rewritten app import");
    }
    if (!tsHelperProps.includes('title: "Preview"') || !tsHelperProps.includes("count: 0")) {
      throw new Error("Imported TS helper bundle missing inferred preview props");
    }

    const importedTsHelperBundle = await importModule(join(importedTsHelperBundleDir, "bundle.mjs"));
    if (typeof importedTsHelperBundle.mount !== "function" || !importedTsHelperBundle.root?.scopeId) {
      throw new Error("Imported TS helper bundle missing direct bundle contract");
    }
  } finally {
    rmSync(importedTsHelperBundleDir, { recursive: true, force: true });
  }
}, 120_000);

test("imported observable shared state wakes component updates", async () => {
  const appDir = mkdtempSync(join(tmpdir(), "weiv-observable-app-"));
  const bundleDir = mkdtempSync(join(tmpdir(), "weiv-observable-bundle-"));

  try {
    writeFileSync(
      join(appDir, "shared.ts"),
      `import { observable } from "@weiv/runtime";

export const shared = observable({
  count: 1,
  label: "steady",
  items: ["first"],
});
export const sharedAlias = shared;

export function incrementShared() {
  shared.count += 1;
}
export function appendShared() {
  shared.items.push("second");
}
`,
      "utf8",
    );
    writeFileSync(
      join(appDir, "App.weiv"),
      `<template>
  <section class="shared-observable-app">
    <p class="count">{{ shared.count }}</p>
    <p class="alias-count">{{ sharedAlias.count }}</p>
    <p class="label">{{ shared.label }}</p>
    <p class="item-count">{{ shared.items.length }}</p>
    <p class="unrelated">{{ local }}</p>
    <button class="increment" on:click="incrementShared">Increment shared</button>
    <button class="append" on:click="appendShared">Append shared</button>
  </section>
</template>

<script lang="ts">
  import { appendShared, incrementShared, shared, sharedAlias } from "./shared.ts";
  let local = "stable";
</script>
`,
      "utf8",
    );

    emitApp(join(appDir, "App.weiv"), bundleDir);

    const bundleModule = await importModule(join(bundleDir, "bundle.mjs"));
    const fakeDocument = new FakeDocument();
    const appTarget = fakeDocument.createElement("div");
    appTarget.setAttribute("id", "app");
    fakeDocument.body.append(appTarget);
    installDocument(fakeDocument);

    bundleModule.mount(appTarget, {});

    const count = findElement(fakeDocument.body, byClass("count"));
    if (!count || count.textContent.trim() !== "1") {
      throw new Error("Observable app did not render initial shared count");
    }
    const aliasCount = findElement(fakeDocument.body, byClass("alias-count"));
    if (!aliasCount || aliasCount.textContent.trim() !== "1") {
      throw new Error("Observable app did not render initial aliased count");
    }

    const unrelated = findElement(fakeDocument.body, byClass("unrelated"));
    const unrelatedText = unrelated?.childNodes[0];
    if (!(unrelatedText instanceof FakeTextNode) || unrelatedText.data !== "stable") {
      throw new Error("Observable app did not render the unrelated binding");
    }
    const label = findElement(fakeDocument.body, byClass("label"));
    const labelText = label?.childNodes[0];
    if (!(labelText instanceof FakeTextNode) || labelText.data !== "steady") {
      throw new Error("Observable app did not render the sibling property");
    }
    let labelReads = 0;
    let labelData = labelText.data;
    Object.defineProperty(labelText, "data", {
      get() {
        labelReads += 1;
        return labelData;
      },
      set(value: string) {
        labelData = value;
      },
    });
    let unrelatedReads = 0;
    let unrelatedData = unrelatedText.data;
    Object.defineProperty(unrelatedText, "data", {
      get() {
        unrelatedReads += 1;
        return unrelatedData;
      },
      set(value: string) {
        unrelatedData = value;
      },
    });

    const incrementButton = findElement(fakeDocument.body, byClass("increment"));
    if (!incrementButton) {
      throw new Error("Observable app missing increment button");
    }

    click(incrementButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise<void>(resolve => queueMicrotask(resolve));

    if (count.textContent.trim() !== "2") {
      throw new Error(
        `Observable app did not refresh after shared mutation, found ${count.textContent.trim()}`,
      );
    }
    if (aliasCount.textContent.trim() !== "2") {
      throw new Error(
        `Observable alias did not refresh after shared mutation, found ${aliasCount.textContent.trim()}`,
      );
    }
    if (unrelatedReads !== 0) {
      throw new Error(`Shared mutation revisited an unrelated binding ${unrelatedReads} times`);
    }
    if (labelReads !== 1) {
      throw new Error(
        `Shared count mutation should revisit the subscribed binding once; read its sibling property ${labelReads} times`,
      );
    }
    const appendButton = findElement(fakeDocument.body, byClass("append"));
    const itemCount = findElement(fakeDocument.body, byClass("item-count"));
    if (!appendButton || !itemCount || itemCount.textContent.trim() !== "1") {
      throw new Error("Observable app did not render the array length");
    }
    click(appendButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise<void>(resolve => queueMicrotask(resolve));
    if (itemCount.textContent.trim() !== "2") {
      throw new Error(
        `Array index write did not update direct length binding: ${itemCount.textContent.trim()}`,
      );
    }
    if (appTarget.replaceChildrenCalls !== 1) {
      throw new Error("Observable app rerendered the root instead of patching in place");
    }
  } finally {
    rmSync(appDir, { recursive: true, force: true });
    rmSync(bundleDir, { recursive: true, force: true });
  }
}, 120_000);

test("TodoMVC direct modules and app emit behave correctly", async () => {
  const modules = await loadModules({
    "App.mjs": emitDirectBrowserModule("test/examples/todomvc/App.weiv"),
    "TodoFooter.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoFooter.weiv"),
    "TodoHeader.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoHeader.weiv"),
    "TodoItem.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoItem.weiv"),
    "TodoList.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoList.weiv"),
    "TodoTextInput.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoTextInput.weiv"),
    "ClassicTodoItem.mjs": emitDirectBrowserModule("test/examples/classic-todo/TodoItem.weiv"),
    "ClassicTodoList.mjs": emitDirectBrowserModule("test/examples/classic-todo/TodoList.weiv"),
  });

  const todomvcDirectAppModule = modules["App.mjs"];
  const classicTodoItemModule = modules["ClassicTodoItem.mjs"];
  const classicTodoListModule = modules["ClassicTodoList.mjs"];

  if (
    !classicTodoItemModule.css.includes(`[data-weiv-scope="${classicTodoItemModule.scopeId}"] .todo-item`)
  ) {
    throw new Error("TodoItem CSS scope mismatch");
  }
  if (
    !classicTodoListModule.css.includes(`[data-weiv-scope="${classicTodoListModule.scopeId}"] .todo-list`)
  ) {
    throw new Error("TodoList CSS scope mismatch");
  }

  const todomvcDirectDocument = new FakeDocument();
  const todomvcDirectTarget = todomvcDirectDocument.createElement("div");
  todomvcDirectDocument.body.append(todomvcDirectTarget);
  installDocument(todomvcDirectDocument);

  todomvcDirectAppModule.mount(todomvcDirectTarget, { title: "todos" });
  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error(
      `TodoMVC direct mount expected 1 root replaceChildren call, found ${todomvcDirectTarget.replaceChildrenCalls}`,
    );
  }

  let directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map(element =>
    element.textContent.trim(),
  );
  if (directLabels.length !== 5) {
    throw new Error(`TodoMVC direct mount expected 5 labels, found ${directLabels.length}`);
  }

  const directNewTodoInput = findElement(todomvcDirectDocument.body, byClass("newtodo"));
  if (!directNewTodoInput) throw new Error("TodoMVC direct mount missing newtodo input");
  directNewTodoInput.value = "Direct DOM codegen path";
  keydown(directNewTodoInput, "Enter");
  await new Promise<void>(resolve => queueMicrotask(resolve));

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct create flow rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map(element =>
    element.textContent.trim(),
  );
  if (directLabels[0] !== "Direct DOM codegen path") {
    throw new Error("TodoMVC direct create flow did not prepend the new todo");
  }

  let directFilterButtons = findElements(todomvcDirectDocument.body, byTag("button")).filter(element =>
    ["All", "Active", "Completed"].includes(element.textContent.trim()),
  );
  const directActiveButton = directFilterButtons.find(element => element.textContent.trim() === "Active");
  if (!directActiveButton) throw new Error("TodoMVC direct active filter button missing");
  click(directActiveButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct filter change rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map(element =>
    element.textContent.trim(),
  );
  if (directLabels.some(text => text.includes("Port TodoMVC into the verification suite"))) {
    throw new Error("TodoMVC direct active filter still shows completed items");
  }

  const directEditLabel = findElements(todomvcDirectDocument.body, byTag("label")).find(element =>
    element.textContent.includes("Exercise edit, filter, and clear-completed flows"),
  );
  if (!directEditLabel) throw new Error("TodoMVC direct edit target label missing");
  dblclick(directEditLabel);
  await new Promise<void>(resolve => queueMicrotask(resolve));

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct edit-mode entry rerendered the root");
  }
  const directEditInput = findElement(todomvcDirectDocument.body, byClass("edit"));
  if (!directEditInput) throw new Error("TodoMVC direct edit flow did not open edit input");
  directEditInput.value = "Direct path edit flow";
  keydown(directEditInput, "Enter");
  await new Promise<void>(resolve => queueMicrotask(resolve));

  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map(element =>
    element.textContent.trim(),
  );
  if (!directLabels.includes("Direct path edit flow")) {
    throw new Error("TodoMVC direct edit flow did not persist the updated text");
  }

  const directToggles = findElements(todomvcDirectDocument.body, byClass("toggle"));
  const directCreatedToggle = directToggles[0];
  if (!directCreatedToggle) throw new Error("TodoMVC direct toggle flow missing active toggle");
  directCreatedToggle.checked = true;
  change(directCreatedToggle);
  await new Promise<void>(resolve => queueMicrotask(resolve));

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct toggle flow rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map(element =>
    element.textContent.trim(),
  );
  if (directLabels.includes("Direct DOM codegen path")) {
    throw new Error("TodoMVC direct active filter did not drop toggled completed item");
  }

  const todomvcBundleDir = mkdtempSync(join(tmpdir(), "weiv-todomvc-bundle-"));
  try {
    emitApp("test/examples/todomvc/App.weiv", todomvcBundleDir);
    const todomvcBundle = await importModule(join(todomvcBundleDir, "bundle.mjs"));
    const todomvcStyles = readFileSync(join(todomvcBundleDir, "styles.css"), "utf8");
    if (
      !todomvcStyles.includes(".todo-header") ||
      !todomvcStyles.includes(".todo-footer") ||
      !todomvcStyles.includes(".toggle-all") ||
      !todomvcStyles.includes(".newtodo")
    ) {
      throw new Error("TodoMVC bundle missing expected selectors");
    }
    if (typeof todomvcBundle.mount !== "function") {
      throw new Error("TodoMVC bundle missing mount export");
    }

    const fakeDocument = new FakeDocument();
    const appTarget = fakeDocument.createElement("div");
    appTarget.setAttribute("id", "app");
    fakeDocument.body.append(appTarget);
    installDocument(fakeDocument);

    todomvcBundle.mount(appTarget, { title: "todos" });
    if (appTarget.replaceChildrenCalls !== 1) {
      throw new Error(
        `TodoMVC mount expected 1 root replaceChildren call, found ${appTarget.replaceChildrenCalls}`,
      );
    }

    let labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (labels.length !== 5) {
      throw new Error(`TodoMVC mount expected 5 labels, found ${labels.length}`);
    }

    const newTodoInput = findElement(fakeDocument.body, byClass("newtodo"));
    if (!newTodoInput) throw new Error("TodoMVC mount missing newtodo input");
    newTodoInput.value = "Verify browser interaction checks";
    keydown(newTodoInput, "Enter");
    await new Promise<void>(resolve => queueMicrotask(resolve));

    labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (labels[0] !== "Verify browser interaction checks") {
      throw new Error("TodoMVC create flow did not prepend the new todo");
    }

    let filterButtons = findElements(fakeDocument.body, byTag("button")).filter(element =>
      ["All", "Active", "Completed"].includes(element.textContent.trim()),
    );
    let activeButton = filterButtons.find(element => element.textContent.trim() === "Active");
    if (!activeButton) throw new Error("TodoMVC active filter button missing");
    click(activeButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));

    labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (labels.some(text => text.includes("Port TodoMVC into the verification suite"))) {
      throw new Error("TodoMVC active filter still shows completed items");
    }

    const activeLabels = findElements(fakeDocument.body, byTag("label"));
    const editLabel = activeLabels.find(element =>
      element.textContent.includes("Exercise edit, filter, and clear-completed flows"),
    );
    if (!editLabel) throw new Error("TodoMVC edit target label missing");
    const replaceChildrenCallsBeforeEdit = appTarget.replaceChildrenCalls;
    dblclick(editLabel);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    if (appTarget.replaceChildrenCalls !== replaceChildrenCallsBeforeEdit) {
      throw new Error("TodoMVC edit-mode entry rerendered the app root instead of the item boundary");
    }

    const editInput = findElement(fakeDocument.body, byClass("edit"));
    if (!editInput) throw new Error("TodoMVC edit flow did not open edit input");
    editInput.value = "Exercise edit, filter, clear-completed, and dev flows";
    keydown(editInput, "Enter");
    await new Promise<void>(resolve => queueMicrotask(resolve));

    labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (!labels.includes("Exercise edit, filter, clear-completed, and dev flows")) {
      throw new Error("TodoMVC edit flow did not persist the updated text");
    }

    const activeToggles = findElements(fakeDocument.body, byClass("toggle"));
    const createdToggle = activeToggles[0];
    if (!createdToggle) throw new Error("TodoMVC toggle flow missing active toggle");
    createdToggle.checked = true;
    change(createdToggle);
    await new Promise<void>(resolve => queueMicrotask(resolve));

    labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (labels.includes("Verify browser interaction checks")) {
      throw new Error("TodoMVC active filter did not drop toggled completed item");
    }

    filterButtons = findElements(fakeDocument.body, byTag("button")).filter(element =>
      ["All", "Active", "Completed"].includes(element.textContent.trim()),
    );
    const allButton = filterButtons.find(element => element.textContent.trim() === "All");
    if (!allButton) throw new Error("TodoMVC all filter button missing");
    click(allButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));

    const clearCompletedButton = findElements(
      fakeDocument.body,
      byTagAndClass("button", "clear-completed"),
    )[0];
    if (!clearCompletedButton) throw new Error("TodoMVC clear completed button missing");
    click(clearCompletedButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));

    labels = findElements(fakeDocument.body, byTag("label")).map(element => element.textContent.trim());
    if (
      labels.includes("Port TodoMVC into the verification suite") ||
      labels.includes("Expose the polished preview on the LAN server") ||
      labels.includes("Verify browser interaction checks")
    ) {
      throw new Error("TodoMVC clear completed flow did not remove completed items");
    }
  } finally {
    rmSync(todomvcBundleDir, { recursive: true, force: true });
  }

  const todomvcDirectBundleDir = mkdtempSync(join(tmpdir(), "weiv-todomvc-direct-bundle-"));
  try {
    emitApp("test/examples/todomvc/App.weiv", todomvcDirectBundleDir);
    const directBundleModule = await importModule(join(todomvcDirectBundleDir, "bundle.mjs"));
    const directBundleMain = readFileSync(join(todomvcDirectBundleDir, "main.mjs"), "utf8");
    if (!directBundleMain.includes("WeivApp.mount(target, props);")) {
      throw new Error("TodoMVC direct bundle missing browser bootstrap");
    }

    const directBundleDocument = new FakeDocument();
    const directBundleTarget = directBundleDocument.createElement("div");
    directBundleDocument.body.append(directBundleTarget);
    installDocument(directBundleDocument);

    directBundleModule.mount(directBundleTarget, { title: "todos" });
    if (directBundleTarget.replaceChildrenCalls !== 1) {
      throw new Error(
        `TodoMVC direct bundle mount expected 1 root replaceChildren call, found ${directBundleTarget.replaceChildrenCalls}`,
      );
    }

    const bundledDirectNewTodoInput = findElement(directBundleDocument.body, byClass("newtodo"));
    if (!bundledDirectNewTodoInput) throw new Error("TodoMVC direct bundle missing newtodo input");
    bundledDirectNewTodoInput.value = "Direct app emit path";
    keydown(bundledDirectNewTodoInput, "Enter");
    await new Promise<void>(resolve => queueMicrotask(resolve));

    const bundledDirectLabels = findElements(directBundleDocument.body, byTag("label")).map(element =>
      element.textContent.trim(),
    );
    if (bundledDirectLabels[0] !== "Direct app emit path") {
      throw new Error("TodoMVC direct bundle create flow did not prepend the new todo");
    }
  } finally {
    rmSync(todomvcDirectBundleDir, { recursive: true, force: true });
  }
}, 120_000);

test("kanib app emit mounts and navigates through routed product flows", async () => {
  const kanibBundleDir = mkdtempSync(join(tmpdir(), "weiv-kanib-bundle-"));
  try {
    emitApp("test/examples/kanib/App.weiv", kanibBundleDir);
    const kanibBundle = await importModule(join(kanibBundleDir, "bundle.mjs"));
    const sharedModule = managedModules(kanibBundleDir);
    const observableModule = readFileSync(join(kanibBundleDir, "__weiv_runtime", "index.js"), "utf8");
    const runtimeIndex = readFileSync(join(kanibBundleDir, "__weiv_runtime", "index.js"), "utf8");

    if (!sharedModule.includes('import { observable } from "../__weiv_runtime/observable.js";')) {
      throw new Error("Kanib bundle did not preserve observable helper import");
    }
    if (!sharedModule.includes("export const workspaceShared =")) {
      throw new Error("Kanib bundle did not create shared state through observable()");
    }
    if (!observableModule.includes('export { observable } from "./observable.js";')) {
      throw new Error("Kanib bundle did not include the observable runtime entry module");
    }
    if (!runtimeIndex.includes('export { createRouter } from "./router.js";')) {
      throw new Error("Kanib bundle did not include the router runtime entry");
    }
    const observableLeafModule = readFileSync(
      join(kanibBundleDir, "__weiv_runtime", "observable.js"),
      "utf8",
    );
    if (!observableLeafModule.includes('const WEIV_OBSERVABLE = Symbol.for("weiv.observable");')) {
      throw new Error("Kanib bundle did not include the observable runtime module");
    }

    const fakeDocument = new FakeDocument();
    const appTarget = fakeDocument.createElement("div");
    appTarget.setAttribute("id", "app");
    fakeDocument.body.append(appTarget);
    installDocument(fakeDocument);
    installRouterWindow("/");

    kanibBundle.mount(appTarget, {});
    await new Promise(resolve => queueMicrotask(resolve));

    if (appTarget.replaceChildrenCalls !== 1) {
      throw new Error(
        `Kanib mount expected 1 root replaceChildren call, found ${appTarget.replaceChildrenCalls}`,
      );
    }
    if (!appTarget.textContent.includes("Compiler Lab")) {
      throw new Error("Kanib did not render header content");
    }
    if (!appTarget.textContent.includes("Compiler Lab overview")) {
      throw new Error("Kanib did not render the overview route on first mount");
    }
    if (!appTarget.textContent.includes("4 notifications")) {
      throw new Error("Kanib did not render initial notification count");
    }

    const openNotificationsButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Open notifications"),
    );
    if (!openNotificationsButton) throw new Error("Kanib is missing open notifications header action");
    click(openNotificationsButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Notifications")) {
      throw new Error("Kanib did not navigate to the notifications route");
    }
    if (!appTarget.textContent.includes("unread")) {
      throw new Error("Kanib notifications route did not render unread summary");
    }

    const designSystemsButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Design Systems"),
    );
    if (!designSystemsButton) throw new Error("Kanib is missing Design Systems workspace switch action");
    click(designSystemsButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Design Systems overview")) {
      throw new Error("Kanib did not switch to the Design Systems workspace");
    }
    if (!appTarget.textContent.includes("Define token-ready shell spacing scale")) {
      throw new Error("Kanib right panel did not update to the selected Design Systems issue");
    }

    const themeEngineProjectButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Theme Engine"),
    );
    if (!themeEngineProjectButton) throw new Error("Kanib is missing Theme Engine project switch action");
    click(themeEngineProjectButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Theme empty states for light + high-contrast")) {
      throw new Error("Kanib did not switch right panel selection after changing project");
    }

    const issuesButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Issues"),
    );
    if (!issuesButton) throw new Error("Kanib is missing issues navigation");
    click(issuesButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Issue list")) {
      throw new Error("Kanib did not navigate to the issue list route");
    }
    if (!appTarget.textContent.includes("Theme empty states for light + high-contrast")) {
      throw new Error("Kanib issue list did not scope to the active Design Systems project");
    }

    const openButtons = findElements(fakeDocument.body, byTag("button")).filter(
      element => element.textContent.trim() === "Open",
    );
    if (openButtons.length === 0) {
      throw new Error("Kanib issue list is missing open buttons");
    }

    const boardButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Board"),
    );
    if (!boardButton) throw new Error("Kanib is missing board navigation");
    click(boardButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Backlog")) {
      throw new Error("Kanib did not navigate to the board route");
    }
    if (!appTarget.textContent.includes("1 issues")) {
      throw new Error("Kanib board did not render the expected initial column counts");
    }

    const advanceButtons = findElements(fakeDocument.body, byTag("button")).filter(
      element => element.textContent.trim() === "Advance",
    );
    if (advanceButtons.length === 0) {
      throw new Error("Kanib board is missing advance actions");
    }
    click(advanceButtons[0]);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("0 issues")) {
      throw new Error("Kanib board advance action did not refresh grouped counts");
    }

    click(issuesButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));
    click(openButtons[0]);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("Implementation notes")) {
      throw new Error("Kanib did not navigate into issue detail");
    }

    const noteInput = findElement(fakeDocument.body, byTagAndClass("input", "issue-detail-page__input"));
    if (!noteInput) throw new Error("Kanib detail route is missing the comment composer input");
    noteInput.value = "Comment from routed test";
    change(noteInput);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    const postButton = findElements(fakeDocument.body, byTag("button")).find(
      element => element.textContent.trim() === "Post",
    );
    if (!postButton) throw new Error("Kanib detail route is missing comment post action");
    click(postButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("You · 0m · Comment from routed test")) {
      throw new Error("Kanib detail comment post did not append to recent activity");
    }

    const saveButton = findElements(fakeDocument.body, byTag("button")).find(
      element => element.textContent.trim() === "Advance status and save",
    );
    if (!saveButton) throw new Error("Kanib detail route is missing the save action");
    click(saveButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => setTimeout(resolve, 0));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("3 notifications")) {
      throw new Error("Kanib detail save did not update shared notification count");
    }

    const clearNotificationsButton = findElements(fakeDocument.body, byTag("button")).find(element =>
      element.textContent.includes("Clear notifications"),
    );
    if (!clearNotificationsButton) throw new Error("Kanib is missing the clear notifications button");
    click(clearNotificationsButton);
    await new Promise<void>(resolve => queueMicrotask(resolve));
    await new Promise(resolve => queueMicrotask(resolve));

    if (!appTarget.textContent.includes("0 notifications")) {
      throw new Error("Kanib clear notifications did not patch the shared notification count");
    }
  } finally {
    rmSync(kanibBundleDir, { recursive: true, force: true });
  }
}, 120_000);
