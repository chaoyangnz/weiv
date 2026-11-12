const idCounters = new Map();

export function createId(prefix = "weiv") {
  const current = idCounters.get(prefix) ?? 0;
  const next = current + 1;
  idCounters.set(prefix, next);
  return `${prefix}-${next}`;
}

export function createControllableState(initialValue) {
  let value = initialValue;
  const listeners = new Set();

  function notify() {
    for (const listener of listeners) listener(value);
  }

  return {
    get value() {
      return value;
    },
    set(nextValue) {
      if (Object.is(value, nextValue)) return;
      value = nextValue;
      notify();
    },
    subscribe(listener) {
      listeners.add(listener);
      listener(value);
      return () => listeners.delete(listener);
    },
  };
}

export function createDialogController({
  initialOpen = false,
  closeOnEscape = true,
  closeOnOutsidePointer = true,
  restoreFocus = true,
  modal = true,
  role = "dialog",
} = {}) {
  const state = createControllableState(Boolean(initialOpen));
  const labelId = createId("wv-dialog-label");
  const descriptionId = createId("wv-dialog-description");

  let contentElement = null;
  let triggerElement = null;
  let previousActiveElement = null;

  function canFocus(element) {
    return typeof element?.focus === "function";
  }

  function openDialog({ trigger } = {}) {
    previousActiveElement = globalThis?.document?.activeElement ?? null;
    if (trigger) triggerElement = trigger;
    state.set(true);
  }

  function closeDialog({ restoreFocusTo } = {}) {
    state.set(false);

    if (!restoreFocus) return;

    const target = restoreFocusTo ?? triggerElement ?? previousActiveElement;
    if (canFocus(target)) {
      target.focus();
    }
  }

  function toggleDialog({ trigger } = {}) {
    if (state.value) {
      closeDialog();
      return;
    }
    openDialog({ trigger });
  }

  function onKeydown(event) {
    if (!closeOnEscape) return false;
    if (!state.value) return false;
    if (event.key !== "Escape") return false;

    event.preventDefault?.();
    closeDialog();
    return true;
  }

  function onPointerDown(event) {
    if (!closeOnOutsidePointer) return false;
    if (!state.value) return false;
    if (!contentElement) return false;

    const target = event.target;
    if (!target || contentElement.contains(target)) return false;

    closeDialog();
    return true;
  }

  function registerContent(element) {
    contentElement = element ?? null;
    return () => {
      if (contentElement === element) contentElement = null;
    };
  }

  function registerTrigger(element) {
    triggerElement = element ?? null;
    return () => {
      if (triggerElement === element) triggerElement = null;
    };
  }

  return {
    get open() {
      return state.value;
    },
    get labelId() {
      return labelId;
    },
    get descriptionId() {
      return descriptionId;
    },
    openDialog,
    closeDialog,
    toggleDialog,
    onKeydown,
    onPointerDown,
    registerContent,
    registerTrigger,
    getDialogA11yProps({ labelledBy, describedBy, role: nextRole } = {}) {
      return {
        role: nextRole ?? role,
        "aria-modal": modal ? "true" : undefined,
        "aria-labelledby": labelledBy ?? labelId,
        "aria-describedby": describedBy ?? descriptionId,
      };
    },
    getTriggerA11yProps({ hasPopup = "dialog" } = {}) {
      return {
        "aria-haspopup": hasPopup,
        "aria-expanded": state.value ? "true" : "false",
      };
    },
    getTitleA11yProps() {
      return { id: labelId };
    },
    getDescriptionA11yProps() {
      return { id: descriptionId };
    },
    subscribe(listener) {
      return state.subscribe(listener);
    },
  };
}

export function createDisclosureController({ initialExpanded = false } = {}) {
  const state = createControllableState(Boolean(initialExpanded));
  const contentId = createId("wv-disclosure-content");

  return {
    get expanded() {
      return state.value;
    },
    get contentId() {
      return contentId;
    },
    expand() {
      state.set(true);
    },
    collapse() {
      state.set(false);
    },
    toggle() {
      state.set(!state.value);
    },
    getTriggerA11yProps({ controls = contentId } = {}) {
      return {
        "aria-expanded": state.value ? "true" : "false",
        "aria-controls": controls,
      };
    },
    getContentA11yProps({ id = contentId } = {}) {
      return {
        id,
        hidden: state.value ? undefined : true,
      };
    },
    subscribe(listener) {
      return state.subscribe(listener);
    },
  };
}

export function createTabsController({
  tabs = [],
  initialValue,
  activationMode = "automatic",
  orientation = "horizontal",
} = {}) {
  const normalizedTabs = tabs.map(tab =>
    typeof tab === "string" ? { value: tab, disabled: false } : { disabled: false, ...tab },
  );

  const firstEnabled = normalizedTabs.find(tab => !tab.disabled)?.value ?? null;
  const initialSelected = initialValue ?? firstEnabled;

  const selectedState = createControllableState(initialSelected);
  const focusedState = createControllableState(initialSelected);
  const tablistId = createId("wv-tabs-list");

  function values() {
    return normalizedTabs.map(tab => tab.value);
  }

  function isDisabled(value) {
    return normalizedTabs.find(tab => tab.value === value)?.disabled ?? true;
  }

  function moveFocus(direction) {
    const candidates = values().filter(value => !isDisabled(value));
    if (candidates.length === 0) return;

    const current = focusedState.value;
    const startIndex = Math.max(candidates.indexOf(current), 0);
    const nextIndex = (startIndex + direction + candidates.length) % candidates.length;
    const nextValue = candidates[nextIndex];

    focusedState.set(nextValue);
    if (activationMode === "automatic") selectedState.set(nextValue);
  }

  return {
    get selectedValue() {
      return selectedState.value;
    },
    get focusedValue() {
      return focusedState.value;
    },
    get tablistId() {
      return tablistId;
    },
    get tabs() {
      return normalizedTabs.slice();
    },
    select(value) {
      if (isDisabled(value)) return;
      selectedState.set(value);
      focusedState.set(value);
    },
    focus(value) {
      if (isDisabled(value)) return;
      focusedState.set(value);
      if (activationMode === "automatic") selectedState.set(value);
    },
    onTabKeydown(event) {
      const isHorizontal = orientation === "horizontal";
      const key = event.key;

      if ((isHorizontal && key === "ArrowRight") || (!isHorizontal && key === "ArrowDown")) {
        event.preventDefault?.();
        moveFocus(1);
        return true;
      }

      if ((isHorizontal && key === "ArrowLeft") || (!isHorizontal && key === "ArrowUp")) {
        event.preventDefault?.();
        moveFocus(-1);
        return true;
      }

      if (key === "Home") {
        event.preventDefault?.();
        const first = normalizedTabs.find(tab => !tab.disabled)?.value;
        if (first != null) {
          focusedState.set(first);
          if (activationMode === "automatic") selectedState.set(first);
        }
        return true;
      }

      if (key === "End") {
        event.preventDefault?.();
        const enabled = normalizedTabs.filter(tab => !tab.disabled);
        const last = enabled[enabled.length - 1]?.value;
        if (last != null) {
          focusedState.set(last);
          if (activationMode === "automatic") selectedState.set(last);
        }
        return true;
      }

      if (key === "Enter" || key === " ") {
        if (activationMode === "manual" && focusedState.value != null) {
          event.preventDefault?.();
          selectedState.set(focusedState.value);
          return true;
        }
      }

      return false;
    },
    getTablistA11yProps() {
      return {
        id: tablistId,
        role: "tablist",
        "aria-orientation": orientation,
      };
    },
    getTabA11yProps(value) {
      const selected = selectedState.value === value;
      return {
        role: "tab",
        "aria-selected": selected ? "true" : "false",
        "aria-controls": `${tablistId}-panel-${value}`,
        id: `${tablistId}-tab-${value}`,
        tabIndex: focusedState.value === value ? 0 : -1,
        "data-state": selected ? "active" : "inactive",
        "data-disabled": isDisabled(value) ? "true" : undefined,
      };
    },
    getPanelA11yProps(value) {
      const selected = selectedState.value === value;
      return {
        role: "tabpanel",
        id: `${tablistId}-panel-${value}`,
        "aria-labelledby": `${tablistId}-tab-${value}`,
        hidden: selected ? undefined : true,
      };
    },
    subscribe(listener) {
      const notify = () => {
        listener({
          selectedValue: selectedState.value,
          focusedValue: focusedState.value,
        });
      };

      const unsubs = [selectedState.subscribe(notify), focusedState.subscribe(notify)];
      return () => {
        for (const unsub of unsubs) unsub();
      };
    },
  };
}
