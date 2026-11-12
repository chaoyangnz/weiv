import { createDisclosureController, createTabsController } from "../../../../packages/ui-core/src/index.js";

export default {
  title: "UI Core/Disclosure + Tabs",
};

export const DisclosureBasics = () => {
  const disclosure = createDisclosureController();

  const root = document.createElement("div");
  root.style.display = "grid";
  root.style.gap = "12px";
  root.style.maxWidth = "560px";

  const trigger = document.createElement("button");
  trigger.className = "wv-button";
  trigger.textContent = "Toggle details";

  const panel = document.createElement("div");
  panel.style.background = "var(--weiv-color-surface)";
  panel.style.border = "1px solid var(--weiv-color-border)";
  panel.style.borderRadius = "var(--weiv-radius-md)";
  panel.style.padding = "12px";
  panel.textContent = "Panel content: release notes and rollout checklist.";

  const sync = () => {
    const triggerProps = disclosure.getTriggerA11yProps();
    trigger.setAttribute("aria-expanded", triggerProps["aria-expanded"]);
    trigger.setAttribute("aria-controls", triggerProps["aria-controls"]);

    const contentProps = disclosure.getContentA11yProps();
    panel.id = contentProps.id;
    panel.hidden = Boolean(contentProps.hidden);
  };

  trigger.addEventListener("click", () => disclosure.toggle());
  disclosure.subscribe(sync);

  root.append(trigger, panel);
  return root;
};

DisclosureBasics.parameters = {
  docs: {
    source: {
      code: `import { createDisclosureController } from "@weivjs/ui-core";

const disclosure = createDisclosureController();
trigger.addEventListener("click", () => disclosure.toggle());

disclosure.subscribe(() => {
  const triggerProps = disclosure.getTriggerA11yProps();
  const contentProps = disclosure.getContentA11yProps();
});`,
    },
  },
};

export const TabsBasics = () => {
  const tabs = createTabsController({
    tabs: ["Overview", "Activity", "Settings"],
    initialValue: "Overview",
    activationMode: "automatic",
  });

  const root = document.createElement("div");
  root.style.display = "grid";
  root.style.gap = "12px";
  root.style.maxWidth = "680px";

  const tablist = document.createElement("div");
  tablist.style.display = "flex";
  tablist.style.gap = "8px";

  const panel = document.createElement("section");
  panel.style.background = "var(--weiv-color-surface)";
  panel.style.border = "1px solid var(--weiv-color-border)";
  panel.style.borderRadius = "var(--weiv-radius-md)";
  panel.style.padding = "14px";

  const labels = tabs.tabs.map(tab => tab.value);

  for (const label of labels) {
    const button = document.createElement("button");
    button.className = "wv-button";
    button.style.minWidth = "120px";
    button.textContent = label;

    button.addEventListener("click", () => tabs.select(label));
    button.addEventListener("keydown", event => {
      const handled = tabs.onTabKeydown(event);
      if (!handled) return;

      const focused = tabs.focusedValue;
      const target = tablist.querySelector(`[data-tab-value="${focused}"]`);
      if (target instanceof HTMLButtonElement) target.focus();
      sync();
    });

    button.dataset.tabValue = label;
    tablist.appendChild(button);
  }

  const sync = () => {
    const tablistProps = tabs.getTablistA11yProps();
    tablist.setAttribute("role", tablistProps.role);
    tablist.setAttribute("aria-orientation", tablistProps["aria-orientation"]);

    for (const child of Array.from(tablist.children)) {
      if (!(child instanceof HTMLButtonElement)) continue;
      const value = child.dataset.tabValue;
      if (!value) continue;

      const props = tabs.getTabA11yProps(value);
      child.setAttribute("role", props.role);
      child.setAttribute("aria-selected", props["aria-selected"]);
      child.setAttribute("aria-controls", props["aria-controls"]);
      child.id = props.id;
      child.tabIndex = props.tabIndex;
      child.dataset.state = props["data-state"];
      child.style.opacity = props["data-state"] === "active" ? "1" : "0.72";
    }

    panel.textContent = `Current tab: ${tabs.selectedValue}`;
  };

  tabs.subscribe(sync);
  root.append(tablist, panel);
  return root;
};

TabsBasics.parameters = {
  docs: {
    source: {
      code: `import { createTabsController } from "@weivjs/ui-core";

const tabs = createTabsController({
  tabs: ["Overview", "Activity", "Settings"],
  activationMode: "automatic",
});

button.addEventListener("keydown", (event) => {
  tabs.onTabKeydown(event);
});`,
    },
  },
};
