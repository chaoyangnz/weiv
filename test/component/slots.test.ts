import { test } from "bun:test";
import {
  FakeDocument,
  assertEqual,
  byTag,
  click,
  emitDirectBrowserModule,
  findElement,
  installDocument,
  loadModules,
  replaceBetweenNodes,
} from "./support";

test("slots and projection patch correctly", async () => {
  const modules = await loadModules({
    "Card.mjs": emitDirectBrowserModule("test/examples/slots/Card.weiv"),
    "CardToggleUsage.mjs": emitDirectBrowserModule("test/examples/slots/CardToggleUsage.weiv"),
    "CardUsage.mjs": emitDirectBrowserModule("test/examples/slots/CardUsage.weiv"),
    "PanelConditionalUsage.mjs": emitDirectBrowserModule("test/examples/slots/PanelConditionalUsage.weiv"),
    "Panel.mjs": emitDirectBrowserModule("test/examples/slots/Panel.weiv"),
    "PanelLoopUsage.mjs": emitDirectBrowserModule("test/examples/slots/PanelLoopUsage.weiv"),
    "PanelNestedCardUsage.mjs": emitDirectBrowserModule("test/examples/slots/PanelNestedCardUsage.weiv"),
    "PanelToggleUsage.mjs": emitDirectBrowserModule("test/examples/slots/PanelToggleUsage.weiv"),
    "PanelUsage.mjs": emitDirectBrowserModule("test/examples/slots/PanelUsage.weiv"),
  });

  const cardDirectModule = modules["Card.mjs"];
  const cardToggleUsageDirectModule = modules["CardToggleUsage.mjs"];
  const cardUsageDirectModule = modules["CardUsage.mjs"];
  const panelConditionalUsageDirectModule = modules["PanelConditionalUsage.mjs"];
  const panelDirectModule = modules["Panel.mjs"];
  const panelLoopUsageDirectModule = modules["PanelLoopUsage.mjs"];
  const panelNestedCardUsageDirectModule = modules["PanelNestedCardUsage.mjs"];
  const panelToggleUsageDirectModule = modules["PanelToggleUsage.mjs"];
  const panelUsageDirectModule = modules["PanelUsage.mjs"];

  const panelFallbackDocument = new FakeDocument();
  const panelFallbackTarget = panelFallbackDocument.createElement("div");
  panelFallbackDocument.body.append(panelFallbackTarget);
  installDocument(panelFallbackDocument);

  panelDirectModule.mount(panelFallbackTarget, {});
  if (!panelFallbackTarget.textContent.includes("Fallback")) {
    throw new Error("Panel direct mount did not render fallback slot content");
  }

  const panelUsageDocument = new FakeDocument();
  const panelUsageTarget = panelUsageDocument.createElement("div");
  panelUsageDocument.body.append(panelUsageTarget);
  installDocument(panelUsageDocument);

  panelUsageDirectModule.mount(panelUsageTarget, { message: "Projected hello" });
  if (!panelUsageTarget.textContent.includes("Projected hello")) {
    throw new Error("PanelUsage direct mount did not render projected default slot content");
  }
  if (panelUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelConditionalUsageDocument = new FakeDocument();
  const panelConditionalUsageTarget = panelConditionalUsageDocument.createElement("div");
  panelConditionalUsageDocument.body.append(panelConditionalUsageTarget);
  installDocument(panelConditionalUsageDocument);

  panelConditionalUsageDirectModule.mount(panelConditionalUsageTarget, {});
  if (!panelConditionalUsageTarget.textContent.includes("Projected panel is closed")) {
    throw new Error("PanelConditionalUsage direct mount did not render the initial projected conditional branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Projected panel is open")) {
    throw new Error("PanelConditionalUsage direct mount incorrectly rendered the alternate projected conditional branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelConditionalUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelConditionalButton = findElement(panelConditionalUsageDocument.body, byTag("button"));
  if (!panelConditionalButton) throw new Error("PanelConditionalUsage direct mount missing button");
  click(panelConditionalButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));

  if (panelConditionalUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("PanelConditionalUsage direct update rerendered the root instead of patching the projected conditional branch");
  }
  if (!panelConditionalUsageTarget.textContent.includes("Projected panel is open")) {
    throw new Error("PanelConditionalUsage direct toggle did not swap the projected conditional branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Projected panel is closed")) {
    throw new Error("PanelConditionalUsage direct toggle left the previous projected branch mounted");
  }

  const panelLoopUsageDocument = new FakeDocument();
  const panelLoopUsageTarget = panelLoopUsageDocument.createElement("div");
  panelLoopUsageDocument.body.append(panelLoopUsageTarget);
  installDocument(panelLoopUsageDocument);

  panelLoopUsageDirectModule.mount(panelLoopUsageTarget, {});
  assertEqual(
    panelLoopUsageTarget.textContent,
    "Toggle completedImplement template binderTest CSS scoping",
    "PanelLoopUsage direct mount text"
  );
  const panelLoopToggleButton = findElement(panelLoopUsageDocument.body, byTag("button"));
  if (!panelLoopToggleButton) throw new Error("PanelLoopUsage direct mount missing button");
  click(panelLoopToggleButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));
  assertEqual(
    panelLoopUsageTarget.textContent,
    "Toggle completedWrite parser fixtures",
    "PanelLoopUsage direct toggle text"
  );

  const panelNestedCardUsageDocument = new FakeDocument();
  const panelNestedCardUsageTarget = panelNestedCardUsageDocument.createElement("div");
  panelNestedCardUsageDocument.body.append(panelNestedCardUsageTarget);
  installDocument(panelNestedCardUsageDocument);

  panelNestedCardUsageDirectModule.mount(panelNestedCardUsageTarget, {});
  if (!panelNestedCardUsageTarget.textContent.includes("Nested dashboard") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested projected body")) {
    throw new Error("PanelNestedCardUsage direct mount missing projected card content");
  }
  const panelNestedCardToggleButton = findElement(panelNestedCardUsageDocument.body, byTag("button"));
  if (!panelNestedCardToggleButton) throw new Error("PanelNestedCardUsage direct mount missing button");
  click(panelNestedCardToggleButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));
  if (!panelNestedCardUsageTarget.textContent.includes("Nested reports") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested projected report body")) {
    throw new Error("PanelNestedCardUsage direct toggle did not patch nested projected card content");
  }

  const panelToggleUsageDocument = new FakeDocument();
  const panelToggleUsageTarget = panelToggleUsageDocument.createElement("div");
  panelToggleUsageDocument.body.append(panelToggleUsageTarget);
  installDocument(panelToggleUsageDocument);

  panelToggleUsageDirectModule.mount(panelToggleUsageTarget, {});
  if (!panelToggleUsageTarget.textContent.includes("Projected first")) {
    throw new Error("PanelToggleUsage direct mount missing initial projected content");
  }
  const panelToggleButton = findElement(panelToggleUsageDocument.body, byTag("button"));
  if (!panelToggleButton) throw new Error("PanelToggleUsage direct mount missing button");
  click(panelToggleButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));
  if (!panelToggleUsageTarget.textContent.includes("Projected second") ||
      panelToggleUsageTarget.textContent.includes("Projected first")) {
    throw new Error("PanelToggleUsage direct toggle did not patch projected content");
  }

  const cardFallbackDocument = new FakeDocument();
  const cardFallbackTarget = cardFallbackDocument.createElement("div");
  cardFallbackDocument.body.append(cardFallbackTarget);
  installDocument(cardFallbackDocument);

  cardDirectModule.mount(cardFallbackTarget, {});
  if (!cardFallbackTarget.textContent.includes("Untitled")) {
    throw new Error("Card direct mount did not render fallback title slot content");
  }

  const cardUsageDocument = new FakeDocument();
  const cardUsageTarget = cardUsageDocument.createElement("div");
  cardUsageDocument.body.append(cardUsageTarget);
  installDocument(cardUsageDocument);

  cardUsageDirectModule.mount(cardUsageTarget, {
    title: "Projected title",
    eyebrow: "Projected eyebrow",
    body: "Projected body",
  });
  if (!cardUsageTarget.textContent.includes("Projected title") ||
      !cardUsageTarget.textContent.includes("Projected eyebrow") ||
      !cardUsageTarget.textContent.includes("Projected body")) {
    throw new Error("CardUsage direct mount did not render projected named slot content");
  }

  const cardToggleDocument = new FakeDocument();
  const cardToggleTarget = cardToggleDocument.createElement("div");
  cardToggleDocument.body.append(cardToggleTarget);
  installDocument(cardToggleDocument);

  cardToggleUsageDirectModule.mount(cardToggleTarget, {});
  if (!cardToggleTarget.textContent.includes("Dashboard") ||
      !cardToggleTarget.textContent.includes("Projected card body")) {
    throw new Error("CardToggleUsage direct mount missing initial named slot content");
  }
  const cardToggleButton = findElement(cardToggleDocument.body, byTag("button"));
  if (!cardToggleButton) throw new Error("CardToggleUsage direct mount missing button");
  click(cardToggleButton);
  await new Promise<void>(resolve => queueMicrotask(resolve));
  if (!cardToggleTarget.textContent.includes("Reports") ||
      !cardToggleTarget.textContent.includes("Projected report body") ||
      cardToggleTarget.textContent.includes("Projected card body")) {
    throw new Error("CardToggleUsage direct toggle did not patch named slot content");
  }

  const imperativeDocument = new FakeDocument();
  const imperativeTarget = imperativeDocument.createElement("div");
  imperativeDocument.body.append(imperativeTarget);
  installDocument(imperativeDocument);

  const start = imperativeDocument.createComment("slot:start");
  const end = imperativeDocument.createComment("slot:end");
  imperativeTarget.append(start);
  imperativeTarget.append(end);
  const fragment = imperativeDocument.createDocumentFragment();
  const initial = imperativeDocument.createElement("p");
  initial.setAttribute("class", "projected");
  initial.append(imperativeDocument.createTextNode("Imperative slot body"));
  fragment.append(initial);
  replaceBetweenNodes(start, end, fragment);
  if (!imperativeTarget.textContent.includes("Imperative slot body")) {
    throw new Error("Imperative slot projection did not insert content between boundaries");
  }

  const replacement = imperativeDocument.createDocumentFragment();
  const next = imperativeDocument.createElement("p");
  next.setAttribute("class", "projected-next");
  next.append(imperativeDocument.createTextNode("Imperative slot replacement"));
  replacement.append(next);
  replaceBetweenNodes(start, end, replacement);
  if (!imperativeTarget.textContent.includes("Imperative slot replacement") ||
      imperativeTarget.textContent.includes("Imperative slot body")) {
    throw new Error("Imperative slot projection did not replace previous content");
  }

  if (!cardDirectModule.css.includes(`[data-weiv-scope="${cardDirectModule.scopeId}"]`)) {
    throw new Error("Card CSS scope marker mismatch");
  }
  if (!panelDirectModule.css.includes(`[data-weiv-scope="${panelDirectModule.scopeId}"]`)) {
    throw new Error("Panel CSS scope marker mismatch");
  }
}, 120_000);
