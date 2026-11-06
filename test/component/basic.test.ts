import { test } from "bun:test";
import {
  FakeDocument,
  byTag,
  click,
  emitLegacyBrowserModule as emitDirectBrowserModule,
  findElement,
  findElements,
  installDocument,
  keydown,
  loadModules,
} from "./support";

test("basic direct components mount and patch selectively", async () => {
  const modules = await loadModules({
    "BasicCounter.mjs": emitDirectBrowserModule("test/examples/basic/basic-counter.weiv"),
    "ConditionalToggleDirect.mjs": emitDirectBrowserModule("test/examples/basic/conditional-toggle.weiv"),
    "FrameceptReactivity.mjs": emitDirectBrowserModule("test/examples/basic/framecept-reactivity.weiv"),
    "NestedConditionalList.mjs": emitDirectBrowserModule("test/examples/basic/nested-conditional-list.weiv"),
    "StaticDynamicClass.mjs": emitDirectBrowserModule("test/examples/basic/static-dynamic-class.weiv"),
    "TimerCallbackDirect.mjs": emitDirectBrowserModule("test/examples/basic/timer-callback.weiv"),
    "TodoListDirect.mjs": emitDirectBrowserModule("test/examples/basic/todo-list.weiv"),
  });

  const basicCounterModule = modules["BasicCounter.mjs"];
  const conditionalToggleDirectModule = modules["ConditionalToggleDirect.mjs"];
  const frameceptReactivityModule = modules["FrameceptReactivity.mjs"];
  const nestedConditionalListModule = modules["NestedConditionalList.mjs"];
  const staticDynamicClassModule = modules["StaticDynamicClass.mjs"];
  const timerCallbackDirectModule = modules["TimerCallbackDirect.mjs"];
  const todoListDirectModule = modules["TodoListDirect.mjs"];

  if (!basicCounterModule.css.includes(`[data-weiv-scope="${basicCounterModule.scopeId}"] .counter-card`)) {
    throw new Error("BasicCounter CSS scope mismatch");
  }

  const directDocument = new FakeDocument();
  const directTarget = directDocument.createElement("div");
  directDocument.body.append(directTarget);
  installDocument(directDocument);

  const directMount = basicCounterModule.mount(directTarget, {
    title: "Counter",
    initialCount: 2,
  });
  if (directTarget.replaceChildrenCalls !== 1) {
    throw new Error(`BasicCounter direct mount expected 1 root replaceChildren call, found ${directTarget.replaceChildrenCalls}`);
  }
  if (!directTarget.textContent.includes("Current count: 2") || !directTarget.textContent.includes("Doubled: 4")) {
    throw new Error("BasicCounter direct mount initial content mismatch");
  }

  const directButton = findElement(directDocument.body, byTag("button"));
  if (!directButton) throw new Error("BasicCounter direct mount missing button");
  click(directButton);

  if (directTarget.replaceChildrenCalls !== 1) {
    throw new Error("BasicCounter direct update rerendered the root instead of patching in place");
  }
  if (!directTarget.textContent.includes("Current count: 3") || !directTarget.textContent.includes("Doubled: 6")) {
    throw new Error("BasicCounter direct click did not patch the updated text");
  }

  for (let i = 0; i < 7; i += 1) {
    click(directButton);
  }
  if (directButton.disabled !== true) {
    throw new Error("BasicCounter direct update did not patch the disabled property");
  }
  if ((directMount.instance.refs as any[]).length === 0) {
    throw new Error("BasicCounter direct mount did not record instance refs");
  }

  const timerDocument = new FakeDocument();
  const timerTarget = timerDocument.createElement("div");
  timerDocument.body.append(timerTarget);
  installDocument(timerDocument);

  timerCallbackDirectModule.mount(timerTarget, {});
  if (!timerTarget.textContent.includes("0")) {
    throw new Error("TimerCallback direct mount initial content mismatch");
  }
  const timerButton = findElement(timerDocument.body, byTag("button"));
  if (!timerButton) throw new Error("TimerCallback direct mount missing button");
  click(timerButton);
  await new Promise((resolve) => setTimeout(resolve, 5));
  if (timerTarget.replaceChildrenCalls !== 1) {
    throw new Error("TimerCallback direct timer update rerendered the root");
  }
  if (!timerTarget.textContent.includes("1")) {
    throw new Error("TimerCallback direct timer callback did not patch state");
  }

  const conditionalDocument = new FakeDocument();
  const conditionalTarget = conditionalDocument.createElement("div");
  conditionalDocument.body.append(conditionalTarget);
  installDocument(conditionalDocument);

  conditionalToggleDirectModule.mount(conditionalTarget, {});
  if (conditionalTarget.replaceChildrenCalls !== 1) {
    throw new Error(`ConditionalToggle direct mount expected 1 root replaceChildren call, found ${conditionalTarget.replaceChildrenCalls}`);
  }
  if (!conditionalTarget.textContent.includes("Panel is closed")) {
    throw new Error("ConditionalToggle direct mount initial branch mismatch");
  }

  const conditionalButton = findElement(conditionalDocument.body, byTag("button"));
  if (!conditionalButton) throw new Error("ConditionalToggle direct mount missing button");
  click(conditionalButton);

  if (conditionalTarget.replaceChildrenCalls !== 1) {
    throw new Error("ConditionalToggle direct update rerendered the root instead of replacing the conditional block");
  }
  if (!conditionalTarget.textContent.includes("Panel is open")) {
    throw new Error("ConditionalToggle direct toggle did not swap to the open branch");
  }
  if (conditionalTarget.textContent.includes("Panel is closed")) {
    throw new Error("ConditionalToggle direct toggle left the closed branch mounted");
  }

  const frameceptDocument = new FakeDocument();
  const frameceptTarget = frameceptDocument.createElement("div");
  frameceptDocument.body.append(frameceptTarget);
  installDocument(frameceptDocument);

  frameceptReactivityModule.mount(frameceptTarget, {});
  let frameceptButtons = findElements(frameceptDocument.body, byTag("button"));
  const selectClipButton = frameceptButtons[0];
  if (!selectClipButton) throw new Error("Framecept reactivity fixture is missing its selection button");
  click(selectClipButton);
  if (!frameceptTarget.textContent.includes("Selected 7") || frameceptTarget.textContent.includes("No clip selected")) {
    throw new Error(`Initially-false conditional did not mount after loop selection: ${frameceptTarget.textContent}`);
  }

  frameceptButtons = findElements(frameceptDocument.body, byTag("button"));
  const loadThumbnailButton = frameceptButtons[1];
  if (!loadThumbnailButton) throw new Error("Framecept reactivity fixture is missing its thumbnail button");
  const thumbnail = findElement(frameceptDocument.body, byTag("img"));
  if (!thumbnail || thumbnail.attributes.get("src") !== "pending") {
    throw new Error("Framecept reactivity fixture has the wrong initial thumbnail source");
  }
  click(loadThumbnailButton);
  await Promise.resolve();
  await Promise.resolve();
  if (thumbnail.attributes.get("src") !== "ready") {
    throw new Error(`Async list replacement did not refresh the repeated binding: ${thumbnail.attributes.get("src")}`);
  }

  const nestedConditionalDocument = new FakeDocument();
  const nestedConditionalTarget = nestedConditionalDocument.createElement("div");
  nestedConditionalDocument.body.append(nestedConditionalTarget);
  installDocument(nestedConditionalDocument);

  nestedConditionalListModule.mount(nestedConditionalTarget, {});
  for (const expected of ["First", "Second", "Third", "After strategies"]) {
    if (!nestedConditionalTarget.textContent.includes(expected)) {
      throw new Error(`Nested conditional list is missing ${expected}: ${nestedConditionalTarget.textContent}`);
    }
  }
  if ((nestedConditionalTarget.textContent.match(/selected/g) ?? []).length !== 1) {
    throw new Error(`Nested conditional list selected the wrong number of entries: ${nestedConditionalTarget.textContent}`);
  }
  let nestedConditionalButtons = findElements(nestedConditionalDocument.body, byTag("button"));
  const nestedConditionalButton = nestedConditionalButtons[0];
  if (!nestedConditionalButton) throw new Error("Nested conditional list is missing its async update button");
  if (nestedConditionalButton.className !== "second") {
    throw new Error(`Bind shorthand did not set the initial class: ${nestedConditionalButton.className}`);
  }

  const firstStrategyButton = nestedConditionalButtons[2];
  if (!firstStrategyButton) throw new Error("Nested conditional list is missing its first loop event button");
  click(firstStrategyButton);
  if (!nestedConditionalTarget.textContent.includes("Firstselected")) {
    throw new Error(`Argument-bearing loop event did not flush its state update: ${nestedConditionalTarget.textContent}`);
  }

  const strategyArticles = findElements(nestedConditionalDocument.body, byTag("article"));
  if (strategyArticles[0]?.attributes.get("style") !== "left: 58%; width: 60px") {
    throw new Error(`Dynamic style binding did not apply its declaration text: ${strategyArticles[0]?.attributes.get("style")}`);
  }

  const appendStrategyButton = nestedConditionalButtons[1];
  if (!appendStrategyButton) throw new Error("Nested conditional list is missing its append button");
  click(appendStrategyButton);
  nestedConditionalButtons = findElements(nestedConditionalDocument.body, byTag("button"));
  if (!nestedConditionalTarget.textContent.includes("Fourth")) {
    throw new Error(`Reactive loop append did not render the new entry: ${nestedConditionalTarget.textContent}`);
  }
  for (const title of ["First", "Second", "Third", "Fourth"]) {
    if ((nestedConditionalTarget.textContent.match(new RegExp(title, "g")) ?? []).length !== 1) {
      throw new Error(`Reactive loop append duplicated ${title}: ${nestedConditionalTarget.textContent}`);
    }
  }

  click(nestedConditionalButton);
  await new Promise((resolve) => setTimeout(resolve, 0));
  if (nestedConditionalButton.className !== "third") {
    throw new Error(`Bind shorthand did not update the class: ${nestedConditionalButton.className}`);
  }
  if (!nestedConditionalTarget.textContent.includes("Thirdselected")) {
    throw new Error(`Nested conditional list did not update its loop-local condition: ${nestedConditionalTarget.textContent}`);
  }
  if (nestedConditionalTarget.textContent.includes("Secondselected")) {
    throw new Error(`Nested conditional list left the previous conditional branch mounted: ${nestedConditionalTarget.textContent}`);
  }

  const classDocument = new FakeDocument();
  const classTarget = classDocument.createElement("div");
  classDocument.body.append(classTarget);
  installDocument(classDocument);

  staticDynamicClassModule.mount(classTarget, {});
  const classButton = findElement(classDocument.body, byTag("button"));
  if (!classButton) throw new Error("Static/dynamic class fixture is missing its button");
  if (classButton.className !== "clip") {
    throw new Error(`Dynamic class binding removed the initial static class: ${classButton.className}`);
  }
  click(classButton);
  if (classButton.className !== "clip selected") {
    throw new Error(`Dynamic class binding did not merge the static class: ${classButton.className}`);
  }
  click(classButton);
  if (classButton.className !== "clip") {
    throw new Error(`Dynamic class binding did not preserve the static class after clearing: ${classButton.className}`);
  }

  const todoListDirectDocument = new FakeDocument();
  const todoListDirectTarget = todoListDirectDocument.createElement("div");
  todoListDirectDocument.body.append(todoListDirectTarget);
  installDocument(todoListDirectDocument);

  todoListDirectModule.mount(todoListDirectTarget, { title: "Tasks" });
  if (todoListDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error(`TodoList direct mount expected 1 root replaceChildren call, found ${todoListDirectTarget.replaceChildrenCalls}`);
  }
  if (!todoListDirectTarget.textContent.includes("Showing pending tasks")) {
    throw new Error("TodoList direct mount initial conditional branch mismatch");
  }
  if (!todoListDirectTarget.textContent.includes("Implement template binder") ||
      !todoListDirectTarget.textContent.includes("Test CSS scoping")) {
    throw new Error("TodoList direct mount initial visible items mismatch");
  }
  if (todoListDirectTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("TodoList direct mount still shows completed item in pending mode");
  }

  const todoListDirectButton = findElement(todoListDirectDocument.body, byTag("button"));
  if (!todoListDirectButton) throw new Error("TodoList direct mount missing toggle button");
  click(todoListDirectButton);

  if (todoListDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoList direct toggle rerendered the root instead of replacing only list/conditional blocks");
  }
  if (!todoListDirectTarget.textContent.includes("Showing completed tasks")) {
    throw new Error("TodoList direct toggle did not switch the conditional branch");
  }
  if (!todoListDirectTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("TodoList direct toggle did not swap in the completed-item list");
  }
  if (todoListDirectTarget.textContent.includes("Implement template binder")) {
    throw new Error("TodoList direct toggle left pending items mounted");
  }
}, 120_000);
