import { beforeEach, expect, test } from "bun:test";
import {
  createDialogController,
  createDisclosureController,
  createTabsController,
} from "../../packages/ui-core/src/index.js";

beforeEach(() => {
  (globalThis as any).document = { activeElement: null };
});

test("dialog closes on Escape when open", () => {
  const dialog = createDialogController({ initialOpen: true });
  const event = { key: "Escape", preventDefault() {} };
  const handled = dialog.onKeydown(event);

  expect(handled).toBe(true);
  expect(dialog.open).toBe(false);
});

test("dialog ignores Escape when closeOnEscape is disabled", () => {
  const dialog = createDialogController({ initialOpen: true, closeOnEscape: false });
  const event = { key: "Escape", preventDefault() {} };
  const handled = dialog.onKeydown(event);

  expect(handled).toBe(false);
  expect(dialog.open).toBe(true);
});

test("dialog closes on outside pointer and ignores inside pointer", () => {
  const dialog = createDialogController({ initialOpen: true });

  const inside = { id: "inside" };
  const outside = { id: "outside" };
  const content = {
    contains(target: unknown) {
      return target === inside;
    },
  };

  dialog.registerContent(content as any);

  const insideHandled = dialog.onPointerDown({ target: inside });
  expect(insideHandled).toBe(false);
  expect(dialog.open).toBe(true);

  const outsideHandled = dialog.onPointerDown({ target: outside });
  expect(outsideHandled).toBe(true);
  expect(dialog.open).toBe(false);
});

test("dialog ignores outside pointer when closeOnOutsidePointer is disabled", () => {
  const dialog = createDialogController({
    initialOpen: true,
    closeOnOutsidePointer: false,
  });

  const content = {
    contains() {
      return false;
    },
  };

  dialog.registerContent(content as any);
  const handled = dialog.onPointerDown({ target: { id: "outside" } });
  expect(handled).toBe(false);
  expect(dialog.open).toBe(true);
});

test("dialog restores focus to trigger when closed", () => {
  let focused = false;
  const trigger = {
    focus() {
      focused = true;
    },
  };

  const dialog = createDialogController();
  dialog.registerTrigger(trigger as any);

  dialog.openDialog({ trigger: trigger as any });
  dialog.closeDialog();

  expect(focused).toBe(true);
});

test("dialog can skip focus restore when configured", () => {
  let focused = false;
  const trigger = {
    focus() {
      focused = true;
    },
  };

  const dialog = createDialogController({ restoreFocus: false });
  dialog.registerTrigger(trigger as any);
  dialog.openDialog({ trigger: trigger as any });
  dialog.closeDialog();

  expect(focused).toBe(false);
});

test("dialog exposes baseline a11y props", () => {
  const dialog = createDialogController();

  const props = dialog.getDialogA11yProps();
  expect(props.role).toBe("dialog");
  expect(props["aria-modal"]).toBe("true");
  expect(props["aria-labelledby"]).toBe(dialog.labelId);
  expect(props["aria-describedby"]).toBe(dialog.descriptionId);
});

test("disclosure exposes expanded state and linked props", () => {
  const disclosure = createDisclosureController();
  const triggerProps = disclosure.getTriggerA11yProps();
  const contentProps = disclosure.getContentA11yProps();

  expect(disclosure.expanded).toBe(false);
  expect(triggerProps["aria-expanded"]).toBe("false");
  expect(triggerProps["aria-controls"]).toBe(disclosure.contentId);
  expect(contentProps.id).toBe(disclosure.contentId);
  expect(contentProps.hidden).toBe(true);

  disclosure.expand();
  const expandedContentProps = disclosure.getContentA11yProps();
  expect(expandedContentProps.hidden).toBeUndefined();
});

test("tabs automatic mode updates selection on arrow navigation", () => {
  const tabs = createTabsController({
    tabs: ["overview", "activity", "settings"],
    initialValue: "overview",
    activationMode: "automatic",
  });

  const handled = tabs.onTabKeydown({ key: "ArrowRight", preventDefault() {} });

  expect(handled).toBe(true);
  expect(tabs.focusedValue).toBe("activity");
  expect(tabs.selectedValue).toBe("activity");
});

test("tabs manual mode only selects on Enter/Space", () => {
  const tabs = createTabsController({
    tabs: ["overview", "activity", "settings"],
    initialValue: "overview",
    activationMode: "manual",
  });

  tabs.onTabKeydown({ key: "ArrowRight", preventDefault() {} });
  expect(tabs.focusedValue).toBe("activity");
  expect(tabs.selectedValue).toBe("overview");

  tabs.onTabKeydown({ key: "Enter", preventDefault() {} });
  expect(tabs.selectedValue).toBe("activity");
});

test("tabs skip disabled entries while navigating", () => {
  const tabs = createTabsController({
    tabs: [{ value: "overview" }, { value: "activity", disabled: true }, { value: "settings" }],
    initialValue: "overview",
  });

  tabs.onTabKeydown({ key: "ArrowRight", preventDefault() {} });
  expect(tabs.focusedValue).toBe("settings");
  expect(tabs.selectedValue).toBe("settings");
});
