// Permanent Zig-reference cases. Run directly with: cyna test cyna-port
// Refresh explicitly with: python3 tools/test-cyna-sfc.py --update-reference-tests
// Review expectation changes; normal tests never regenerate them.
import { parse, ParseError } from .compiler.parser.sfc.parse;
import { SfcSection } from .compiler.parser.sfc.ast;

fn expect_section(actual: SfcSection, expected: [10]usize): void {
    assert(actual.tag_name.start == expected[0]);
    assert(actual.tag_name.end == expected[1]);
    assert(actual.attributes.start == expected[2]);
    assert(actual.attributes.end == expected[3]);
    assert(actual.open_span.start == expected[4]);
    assert(actual.open_span.end == expected[5]);
    assert(actual.content_span.start == expected[6]);
    assert(actual.content_span.end == expected[7]);
    assert(actual.close_span.start == expected[8]);
    assert(actual.close_span.end == expected[9]);
}

test "edge-0" {
    const doc = parse("".bytes()) catch (code) {
        assert(code == ParseError.missing_template);
        return;
    };
    assert(false);
}
test "edge-1" {
    const doc = parse("<template></template>".bytes()) catch (code) {
        assert(code == ParseError.missing_script);
        return;
    };
    assert(false);
}
test "edge-2" {
    const doc = parse("<script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.invalid_section_order);
        return;
    };
    assert(false);
}
test "edge-3" {
    const doc = parse("<style></style>".bytes()) catch (code) {
        assert(code == ParseError.invalid_section_order);
        return;
    };
    assert(false);
}
test "edge-4" {
    const doc = parse("text".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "edge-5" {
    const doc = parse("<".bytes()) catch (code) {
        assert(code == ParseError.unterminated_open_tag);
        return;
    };
    assert(false);
}
test "edge-6" {
    const doc = parse("<template>".bytes()) catch (code) {
        assert(code == ParseError.unterminated_close_tag);
        return;
    };
    assert(false);
}
test "edge-7" {
    const doc = parse("<unknown></unknown>".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "edge-8" {
    const doc = parse("<></>".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "edge-9" {
    const doc = parse("<template></template><script".bytes()) catch (code) {
        assert(code == ParseError.unterminated_open_tag);
        return;
    };
    assert(false);
}
test "edge-10" {
    const doc = parse("<template></template><script lang=\"ts\">".bytes()) catch (code) {
        assert(code == ParseError.unterminated_close_tag);
        return;
    };
    assert(false);
}
test "edge-11" {
    const doc = parse("<template></template><script></script>".bytes()) catch (code) {
        assert(code == ParseError.invalid_script_attributes);
        return;
    };
    assert(false);
}
test "edge-12" {
    const doc = parse("<template></template><script lang='ts'></script>".bytes()) catch (code) {
        assert(code == ParseError.invalid_script_attributes);
        return;
    };
    assert(false);
}
test "edge-13" {
    const doc = parse("<template></template><script lang=\"js\"></script>".bytes()) catch (code) {
        assert(code == ParseError.invalid_script_attributes);
        return;
    };
    assert(false);
}
test "edge-14" {
    const doc = parse("<template></template><template></template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.duplicate_template);
        return;
    };
    assert(false);
}
test "edge-15" {
    const doc = parse("<template></template><script lang=\"ts\"></script><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.duplicate_script);
        return;
    };
    assert(false);
}
test "edge-16" {
    const doc = parse("<template></template><script lang=\"ts\"></script><style></style><style></style>".bytes()) catch (code) {
        assert(code == ParseError.duplicate_style);
        return;
    };
    assert(false);
}
test "edge-17" {
    const doc = parse("<template></template><style></style><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.invalid_section_order);
        return;
    };
    assert(false);
}
test "edge-18" {
    const doc = parse("<script lang=\"ts\"></script><template></template>".bytes()) catch (code) {
        assert(code == ParseError.invalid_section_order);
        return;
    };
    assert(false);
}
test "edge-19" {
    const doc = parse("<template></template><script lang=\"ts\"></script><other></other>".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "edge-20" {
    const doc = parse("<template></template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 10, 10, 21]);
    expect_section(doc.script, [22, 28, 29, 38, 21, 39, 39, 39, 39, 48]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-21" {
    const doc = parse("<template></template><script lang=\"ts\"></script><style></style>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 10, 10, 21]);
    expect_section(doc.script, [22, 28, 29, 38, 21, 39, 39, 39, 39, 48]);
    if doc.style is style {
        expect_section(style, [49, 54, 54, 54, 48, 55, 55, 55, 55, 63]);
    } else {
        assert(false);
    }
}
test "edge-22" {
    const doc = parse("\t\r\n<template></template><script lang=\"ts\"></script> ".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [4, 12, 12, 12, 3, 13, 13, 13, 13, 24]);
    expect_section(doc.script, [27, 33, 34, 43, 26, 44, 44, 44, 44, 53]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-23" {
    const doc = parse("<template>héllo 🌱</template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 21, 21, 32]);
    expect_section(doc.script, [33, 39, 40, 49, 32, 50, 50, 50, 50, 59]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-24" {
    const doc = parse("<template><template>x</template><template/></template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 43, 43, 54]);
    expect_section(doc.script, [55, 61, 62, 71, 54, 72, 72, 72, 72, 81]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-25" {
    const doc = parse("<template><template-extra/></template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 27, 27, 38]);
    expect_section(doc.script, [39, 45, 46, 55, 38, 56, 56, 56, 56, 65]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-26" {
    const doc = parse("<template><template /></template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 22, 22, 33]);
    expect_section(doc.script, [34, 40, 41, 50, 33, 51, 51, 51, 51, 60]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-27" {
    const doc = parse("<template><template>x</template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.unterminated_close_tag);
        return;
    };
    assert(false);
}
test "edge-28" {
    const doc = parse("<template>x</template ><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "edge-29" {
    const doc = parse("< template>x</template><script lang=\"ts\"></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [2, 10, 9, 10, 0, 11, 11, 12, 12, 23]);
    expect_section(doc.script, [24, 30, 31, 40, 23, 41, 41, 41, 41, 50]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-30" {
    const doc = parse("<template></template><script  lang=\"ts\" ></script>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 10, 10, 21]);
    expect_section(doc.script, [22, 28, 30, 39, 21, 41, 41, 41, 41, 50]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "edge-31" {
    const doc = parse("<template></template><script\tlang=\"ts\"></script>".bytes()) catch (code) {
        assert(code == ParseError.unterminated_close_tag);
        return;
    };
    assert(false);
}
test "edge-32" {
    const doc = parse("<template></template><script lang=\"ts\">const x = \"<script>\";</script>".bytes()) catch (code) {
        assert(code == ParseError.unterminated_close_tag);
        return;
    };
    assert(false);
}
test "edge-33" {
    const doc = parse("<template></template><script lang=\"ts\"></script><style scoped>p{color:red}</style>".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 10, 10, 21]);
    expect_section(doc.script, [22, 28, 29, 38, 21, 39, 39, 39, 39, 48]);
    if doc.style is style {
        expect_section(style, [49, 54, 55, 61, 48, 62, 62, 74, 74, 82]);
    } else {
        assert(false);
    }
}
test "edge-34" {
    const doc = parse("<template></template><script lang=\"ts\"></script>trailing".bytes()) catch (code) {
        assert(code == ParseError.unknown_top_level_section);
        return;
    };
    assert(false);
}
test "apps/storybook/stories/ui-core/DialogBasic.weiv" {
    const doc = parse("<template>\n  <section class=\"story-root\">\n    <wui-dialog :data-state=\"open ? 'open' : 'closed'\">\n      <wui-dialog-trigger>\n        <button class=\"wv-button\" @click=\"openDialog\">Open dialog</button>\n      </wui-dialog-trigger>\n      <p class=\"wv-help\">State: {{ open ? \"open\" : \"closed\" }}</p>\n\n      <wui-dialog-overlay\n        class=\"dialog-overlay\"\n        :style=\"open ? 'display:grid' : 'display:none'\"\n        @click=\"onBackdropClick\"\n      >\n        <wui-dialog-content class=\"dialog-content\" @click=\"stopBubbling\">\n        <wui-dialog-title class=\"dialog-title\">Dialog preview</wui-dialog-title>\n        <wui-dialog-description class=\"wv-help\">\n          This canvas now uses the same wui-dialog API shape.\n        </wui-dialog-description>\n        <wui-dialog-footer class=\"dialog-footer\">\n          <button class=\"wv-button\" @click=\"closeDialog\">Confirm</button>\n          <button class=\"wv-button story-cancel\" @click=\"closeDialog\">Cancel</button>\n        </wui-dialog-footer>\n      </wui-dialog-content>\n      </wui-dialog-overlay>\n    </wui-dialog>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  let open = false;\n\n  function openDialog() {\n    open = true;\n  }\n\n  function closeDialog() {\n    open = false;\n  }\n\n  function onBackdropClick() {\n    closeDialog();\n  }\n\n  function stopBubbling(event: MouseEvent) {\n    event.stopPropagation();\n  }\n</script>\n\n<style>\n  .story-root {\n    display: grid;\n    gap: 12px;\n    max-width: 560px;\n  }\n\n  .dialog-overlay {\n    position: fixed;\n    inset: 0;\n    display: grid;\n    place-items: center;\n    background: rgba(7, 15, 31, 0.45);\n    z-index: 999;\n  }\n\n  .dialog-content {\n    width: min(480px, 90vw);\n    background: var(--weiv-color-surface);\n    color: var(--weiv-color-text);\n    border: 1px solid var(--weiv-color-border);\n    border-radius: var(--weiv-radius-lg);\n    padding: 20px;\n    box-shadow: var(--weiv-shadow-md);\n    display: grid;\n    gap: 12px;\n  }\n\n  .dialog-title {\n    display: block;\n    margin: 0;\n    font: 700 18px/1.2 var(--weiv-font-body);\n  }\n\n  .dialog-footer {\n    display: flex;\n    gap: 10px;\n  }\n\n  .story-cancel {\n    background: var(--weiv-color-surface);\n    color: var(--weiv-color-text);\n    border-color: var(--weiv-color-border);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1076, 1076, 1087]);
    expect_section(doc.script, [1090, 1096, 1097, 1106, 1089, 1107, 1107, 1360, 1360, 1369]);
    if doc.style is style {
        expect_section(style, [1372, 1377, 1377, 1377, 1371, 1378, 1378, 2237, 2237, 2245]);
    } else {
        assert(false);
    }
}
test "apps/storybook/stories/ui-core/DialogPreview.weiv" {
    const doc = parse("<template>\n  <section class=\"dialog-story-shell\">\n    <h3>{{ props.title }}</h3>\n    <p class=\"wv-help\">{{ props.description }}</p>\n    <div class=\"dialog-story-actions\">\n      <button class=\"wv-button\" @click=\"emitConfirm\">Confirm</button>\n      <button class=\"wv-button dialog-story-cancel\" @click=\"emitCancel\">Cancel</button>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    title: string;\n    description: string;\n  }\n\n  export interface Emits {\n    confirm: void;\n    cancel: void;\n  }\n\n  export let props: Props;\n\n  function emitConfirm() {\n    emit(\"confirm\");\n  }\n\n  function emitCancel() {\n    emit(\"cancel\");\n  }\n</script>\n\n<style>\n  .dialog-story-shell {\n    display: grid;\n    gap: 12px;\n  }\n\n  .dialog-story-shell h3 {\n    margin: 0;\n    font: 700 18px/1.2 var(--weiv-font-body);\n    color: var(--weiv-color-text);\n  }\n\n  .dialog-story-actions {\n    display: flex;\n    gap: 10px;\n  }\n\n  .dialog-story-cancel {\n    background: var(--weiv-color-surface);\n    color: var(--weiv-color-text);\n    border-color: var(--weiv-color-border);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 353, 353, 364]);
    expect_section(doc.script, [367, 373, 374, 383, 366, 384, 384, 661, 661, 670]);
    if doc.style is style {
        expect_section(style, [673, 678, 678, 678, 672, 679, 679, 1087, 1087, 1095]);
    } else {
        assert(false);
    }
}
test "packages/ui-components/src/WuiDialog.weiv" {
    const doc = parse("<template>\n  <section class=\"wui-dialog\">\n    <button class=\"wv-button wui-dialog__trigger\" @click=\"openDialog\">\n      {{ props.triggerLabel ?? \"Open dialog\" }}\n    </button>\n\n    <div\n      #if=\"open\"\n      class=\"wui-dialog__backdrop\"\n      @click=\"onBackdropClick\"\n      @keydown=\"onBackdropKeydown\"\n      tabindex=\"-1\"\n    >\n      <section class=\"wui-dialog__surface\" :role=\"dialogRole\" :aria-modal=\"ariaModal\" :aria-labelledby=\"labelId\" :aria-describedby=\"descriptionId\">\n        <header class=\"wui-dialog__header\">\n          <h2 class=\"wui-dialog__title\" :id=\"labelId\">{{ props.title ?? \"Dialog\" }}</h2>\n          <button class=\"wv-button wui-dialog__close\" @click=\"closeDialog\">\n            {{ props.closeLabel ?? \"Close\" }}\n          </button>\n        </header>\n\n        <p class=\"wui-dialog__description\" :id=\"descriptionId\">{{ props.description ?? \"Dialog description\" }}</p>\n\n        <div class=\"wui-dialog__body\">\n          <slot>\n            <p class=\"wui-dialog__fallback\">Add dialog content here.</p>\n          </slot>\n        </div>\n      </section>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { createDialogController } from \"@weivjs/ui-core\";\n\n  export interface Props {\n    triggerLabel?: string;\n    title?: string;\n    description?: string;\n    closeLabel?: string;\n  }\n\n  export let props: Props;\n\n  const dialog = createDialogController();\n\n  let open = dialog.open;\n  const a11y = dialog.getDialogA11yProps();\n  const dialogRole = a11y.role;\n  const ariaModal = a11y[\"aria-modal\"];\n  const labelId = dialog.labelId;\n  const descriptionId = dialog.descriptionId;\n\n  dialog.subscribe((nextOpen) => {\n    open = nextOpen;\n  });\n\n  function openDialog() {\n    dialog.openDialog();\n  }\n\n  function closeDialog() {\n    dialog.closeDialog();\n  }\n\n  function onBackdropClick(event: MouseEvent) {\n    const target = event.target as Element | null;\n    if (target?.classList.contains(\"wui-dialog__backdrop\")) {\n      dialog.closeDialog();\n    }\n  }\n\n  function onBackdropKeydown(event: KeyboardEvent) {\n    dialog.onKeydown(event);\n  }\n</script>\n\n<style>\n  .wui-dialog {\n    display: grid;\n    gap: var(--weiv-space-3);\n  }\n\n  .wui-dialog__backdrop {\n    position: fixed;\n    inset: 0;\n    z-index: 60;\n    display: grid;\n    place-items: center;\n    background: rgba(9, 16, 32, 0.48);\n    padding: var(--weiv-space-4);\n  }\n\n  .wui-dialog__surface {\n    width: min(560px, 100%);\n    border-radius: var(--weiv-radius-lg);\n    border: 1px solid var(--weiv-color-border);\n    background: var(--weiv-color-surface);\n    box-shadow: var(--weiv-shadow-md);\n    padding: var(--weiv-space-4);\n    display: grid;\n    gap: var(--weiv-space-3);\n  }\n\n  .wui-dialog__header {\n    display: flex;\n    align-items: center;\n    justify-content: space-between;\n    gap: var(--weiv-space-3);\n  }\n\n  .wui-dialog__title {\n    margin: 0;\n    font: 650 1.05rem/1.2 var(--weiv-font-body);\n  }\n\n  .wui-dialog__description,\n  .wui-dialog__fallback {\n    margin: 0;\n    color: var(--weiv-color-muted);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1090, 1090, 1101]);
    expect_section(doc.script, [1104, 1110, 1111, 1120, 1103, 1121, 1121, 2071, 2071, 2080]);
    if doc.style is style {
        expect_section(style, [2083, 2088, 2088, 2088, 2082, 2089, 2089, 3014, 3014, 3022]);
    } else {
        assert(false);
    }
}
test "packages/ui-components/src/WuiDisclosure.weiv" {
    const doc = parse("<template>\n  <section class=\"wui-disclosure\">\n    <button\n      class=\"wv-button wui-disclosure__trigger\"\n      :aria-expanded=\"ariaExpanded\"\n      :aria-controls=\"controlsId\"\n      @click=\"toggle\"\n    >\n      {{ props.label ?? \"Toggle\" }}\n    </button>\n\n    <div class=\"wui-disclosure__content\" :id=\"controlsId\" :hidden=\"hidden\">\n      <slot>\n        <p class=\"wui-disclosure__fallback\">Disclosure content.</p>\n      </slot>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { createDisclosureController } from \"@weivjs/ui-core\";\n\n  export interface Props {\n    label?: string;\n    initialExpanded?: boolean;\n  }\n\n  export let props: Props;\n\n  const disclosure = createDisclosureController({\n    initialExpanded: props.initialExpanded ?? false,\n  });\n\n  let ariaExpanded = disclosure.getTriggerA11yProps()[\"aria-expanded\"];\n  let controlsId = disclosure.contentId;\n  let hidden = Boolean(disclosure.getContentA11yProps().hidden);\n\n  disclosure.subscribe(() => {\n    const trigger = disclosure.getTriggerA11yProps();\n    const content = disclosure.getContentA11yProps();\n    ariaExpanded = trigger[\"aria-expanded\"];\n    controlsId = trigger[\"aria-controls\"];\n    hidden = Boolean(content.hidden);\n  });\n\n  function toggle() {\n    disclosure.toggle();\n  }\n</script>\n\n<style>\n  .wui-disclosure {\n    display: grid;\n    gap: var(--weiv-space-3);\n  }\n\n  .wui-disclosure__content {\n    border: 1px solid var(--weiv-color-border);\n    border-radius: var(--weiv-radius-md);\n    background: var(--weiv-color-surface);\n    padding: var(--weiv-space-3);\n  }\n\n  .wui-disclosure__fallback {\n    margin: 0;\n    color: var(--weiv-color-muted);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 450, 450, 461]);
    expect_section(doc.script, [464, 470, 471, 480, 463, 481, 481, 1270, 1270, 1279]);
    if doc.style is style {
        expect_section(style, [1282, 1287, 1287, 1287, 1281, 1288, 1288, 1649, 1649, 1657]);
    } else {
        assert(false);
    }
}
test "packages/ui-components/src/WuiTabs.weiv" {
    const doc = parse("<template>\n  <section class=\"wui-tabs\">\n    <div class=\"wui-tabs__list\" role=\"tablist\" aria-orientation=\"horizontal\">\n      <button\n        class=\"wv-button wui-tabs__trigger\"\n        role=\"tab\"\n        :aria-selected=\"overviewSelected\"\n        @click=\"selectOverview\"\n        @keydown=\"handleKeydown\"\n      >\n        Overview\n      </button>\n      <button\n        class=\"wv-button wui-tabs__trigger\"\n        role=\"tab\"\n        :aria-selected=\"activitySelected\"\n        @click=\"selectActivity\"\n        @keydown=\"handleKeydown\"\n      >\n        Activity\n      </button>\n      <button\n        class=\"wv-button wui-tabs__trigger\"\n        role=\"tab\"\n        :aria-selected=\"settingsSelected\"\n        @click=\"selectSettings\"\n        @keydown=\"handleKeydown\"\n      >\n        Settings\n      </button>\n    </div>\n\n    <section class=\"wui-tabs__panel\" role=\"tabpanel\">\n      <div #if=\"selectedValue === 'Overview'\">\n        <slot name=\"overview\">\n          <p class=\"wui-tabs__fallback\">Overview content</p>\n        </slot>\n      </div>\n      <div #if=\"selectedValue === 'Activity'\">\n        <slot name=\"activity\">\n          <p class=\"wui-tabs__fallback\">Activity content</p>\n        </slot>\n      </div>\n      <div #if=\"selectedValue === 'Settings'\">\n        <slot name=\"settings\">\n          <p class=\"wui-tabs__fallback\">Settings content</p>\n        </slot>\n      </div>\n    </section>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { createTabsController } from \"@weivjs/ui-core\";\n\n  export interface Props {\n    activationMode?: \"automatic\" | \"manual\";\n    initialTab?: \"Overview\" | \"Activity\" | \"Settings\";\n  }\n\n  export let props: Props;\n\n  const tabs = createTabsController({\n    tabs: [\"Overview\", \"Activity\", \"Settings\"],\n    initialValue: props.initialTab ?? \"Overview\",\n    activationMode: props.activationMode ?? \"automatic\",\n  });\n\n  let selectedValue = tabs.selectedValue;\n  let overviewSelected = selectedValue === \"Overview\" ? \"true\" : \"false\";\n  let activitySelected = selectedValue === \"Activity\" ? \"true\" : \"false\";\n  let settingsSelected = selectedValue === \"Settings\" ? \"true\" : \"false\";\n\n  tabs.subscribe((state) => {\n    selectedValue = state.selectedValue;\n    overviewSelected = selectedValue === \"Overview\" ? \"true\" : \"false\";\n    activitySelected = selectedValue === \"Activity\" ? \"true\" : \"false\";\n    settingsSelected = selectedValue === \"Settings\" ? \"true\" : \"false\";\n  });\n\n  function selectOverview() {\n    tabs.select(\"Overview\");\n  }\n\n  function selectActivity() {\n    tabs.select(\"Activity\");\n  }\n\n  function selectSettings() {\n    tabs.select(\"Settings\");\n  }\n\n  function handleKeydown(event: KeyboardEvent) {\n    tabs.onTabKeydown(event);\n  }\n</script>\n\n<style>\n  .wui-tabs {\n    display: grid;\n    gap: var(--weiv-space-3);\n  }\n\n  .wui-tabs__list {\n    display: flex;\n    gap: var(--weiv-space-2);\n    flex-wrap: wrap;\n  }\n\n  .wui-tabs__trigger[aria-selected=\"false\"] {\n    opacity: 0.75;\n  }\n\n  .wui-tabs__panel {\n    border: 1px solid var(--weiv-color-border);\n    border-radius: var(--weiv-radius-md);\n    background: var(--weiv-color-surface);\n    padding: var(--weiv-space-3);\n  }\n\n  .wui-tabs__fallback {\n    margin: 0;\n    color: var(--weiv-color-muted);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1391, 1391, 1402]);
    expect_section(doc.script, [1405, 1411, 1412, 1421, 1404, 1422, 1422, 2676, 2676, 2685]);
    if doc.style is style {
        expect_section(style, [2688, 2693, 2693, 2693, 2687, 2694, 2694, 3200, 3200, 3208]);
    } else {
        assert(false);
    }
}
test "test/examples/bare-import/App.weiv" {
    const doc = parse("<template>\n  <section>\n    <h1>{{ headline() }}</h1>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { camelCase } from \"lodash-es\";\n\n  export interface Props {\n    title: string;\n  }\n\n  export let props: Props;\n\n  function headline() {\n    return camelCase(props.title);\n  }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 66, 66, 77]);
    expect_section(doc.script, [80, 86, 87, 96, 79, 97, 97, 282, 282, 291]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/MetricBadge.weiv" {
    const doc = parse("<template>\n  <span class=\"metric-badge\">\n    {{ props.label }}\n  </span>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    label: string;\n    tone: string;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .metric-badge {\n    display: inline-flex;\n    padding: 0.25rem 0.75rem;\n    border-radius: 999px;\n    background: #f4f4f5;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 73, 73, 84]);
    expect_section(doc.script, [87, 93, 94, 103, 86, 104, 104, 201, 201, 210]);
    if doc.style is style {
        expect_section(style, [213, 218, 218, 218, 212, 219, 219, 349, 349, 357]);
    } else {
        assert(false);
    }
}
test "test/examples/basic/NestedConditionalChild.weiv" {
    const doc = parse("<template><output>{{ props.value }}</output></template>\n<script lang=\"ts\">export let props: { value: number };</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 44, 44, 55]);
    expect_section(doc.script, [57, 63, 64, 73, 56, 74, 74, 110, 110, 119]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/TemplatePropChild.weiv" {
    const doc = parse("<template><span>{{ props.describedBy }}</span></template>\n<script lang=\"ts\">export let props: { describedBy: string };</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 46, 46, 57]);
    expect_section(doc.script, [59, 65, 66, 75, 58, 76, 76, 118, 118, 127]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/aria-tabs.weiv" {
    const doc = parse("<template><div role=\"tablist\"><button role=\"tab\" :aria-selected=\"activeTab === 'light'\" @click=\"selectLight\">Light</button><button role=\"tab\" :aria-selected=\"activeTab === 'color'\" @click=\"selectColor\">Color</button></div></template>\n<script lang=\"ts\">\nlet activeTab = \"light\";\nfunction selectLight() { activeTab = \"light\"; }\nfunction selectColor() { activeTab = \"color\"; }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 222, 222, 233]);
    expect_section(doc.script, [235, 241, 242, 251, 234, 252, 252, 374, 374, 383]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/array-methods.weiv" {
    const doc = parse("<template><p>{{ props.items.map(item => item.name).join(separator) }}</p><p>{{ props.items.filter(item => item.active).length }}</p></template>\n<script lang=\"ts\">\nexport let props: { items: { name: string; active: boolean }[] };\nconst separator = \"-\";\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 132, 132, 143]);
    expect_section(doc.script, [145, 151, 152, 161, 144, 162, 162, 252, 252, 261]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/basic-counter.weiv" {
    const doc = parse("<template>\n  <section class=\"counter-card\">\n    <h2>{{ props.title }}</h2>\n\n    <p>Current count: {{ count }}</p>\n    <p>Doubled: {{ doubled() }}</p>\n\n    <button @click=\"increment\" :disabled=\"count >= limit\">\n      Increment\n    </button>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    title: string;\n    initialCount?: number;\n  }\n\n  export let props: Props;\n\n  let count = props.initialCount ?? 0;\n  let limit = 10;\n\n  function doubled() {\n    return count * 2;\n  }\n\n  function increment() {\n    count += 1;\n  }\n</script>\n\n<style>\n  .counter-card {\n    padding: 1rem;\n    border: 1px solid #d4d4d8;\n    border-radius: 16px;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 253, 253, 264]);
    expect_section(doc.script, [267, 273, 274, 283, 266, 284, 284, 544, 544, 553]);
    if doc.style is style {
        expect_section(style, [556, 561, 561, 561, 555, 562, 562, 660, 660, 668]);
    } else {
        assert(false);
    }
}
test "test/examples/basic/compiler-cells-import.weiv" {
    const doc = parse("<template><p>{{ count }} / {{ shared.count }}</p></template>\n<script lang=\"ts\">\n  import { shared } from \"./compiler-cells-state.mjs\";\n  let count = 0;\n  window.addEventListener(\"cells-mixed\", () => { count++; shared.count++; });\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 49, 49, 60]);
    expect_section(doc.script, [62, 68, 69, 78, 61, 79, 79, 230, 230, 239]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/compiler-cells-snapshot.weiv" {
    const doc = parse("<template><p class=\"captured\">{{ captured.nested.count }}</p></template>\n<script lang=\"ts\">\n  import { snapshot } from \"weiv:observable\";\n  const original = { nested: { count: 1 } };\n  let captured = snapshot(original);\n  window.addEventListener(\"snapshot-source\", () => { original.nested.count++; });\n  window.addEventListener(\"snapshot-capture\", () => { captured = snapshot(original); });\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 61, 61, 72]);
    expect_section(doc.script, [74, 80, 81, 90, 73, 91, 91, 391, 391, 400]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/compiler-cells.weiv" {
    const doc = parse("<template>\n  <p class=\"count\">{{ count }}</p>\n  <p class=\"object\">{{ state.n }}</p>\n  <p class=\"shadow\">{{ shadow() }}</p>\n  <button @click=\"increment\">Increment</button>\n</template>\n<script lang=\"ts\">\n  export let props: { initial: number };\n  let count = props.initial;\n  let state = { n: 0 };\n  let callable: any;\n  let optional: any = null;\n  function shadow() { let count = 40; return ++count; }\n  function increment() { count++; }\n  window.addEventListener(\"cells-write\", () => { count++; state.n++; });\n  window.addEventListener(\"cells-async\", (event) => {\n    event.detail.result = (async () => {\n      count++;\n      await event.detail.first;\n      count++;\n      await event.detail.second;\n      count++;\n    })();\n  });\n  window.addEventListener(\"cells-detached\", () => {\n    void Promise.resolve().then(() => { count++; });\n  });\n  window.addEventListener(\"cells-expression\", (event) => {\n    event.detail.post = count++;\n    event.detail.pre = ++count;\n    event.detail.shorthand = { count };\n    callable = function () { \"use strict\"; return this === undefined; };\n    event.detail.receiver = callable();\n    event.detail.parenthesizedReceiver = (callable as any)();\n    event.detail.sequenceReceiver = (0, callable)();\n    callable = undefined;\n    event.detail.argumentCalls = 0;\n    event.detail.optional = callable?.(event.detail.argumentCalls++);\n    callable = 5;\n    try { callable(event.detail.argumentCalls++); }\n    catch (error) { event.detail.nonCallable = error instanceof TypeError; }\n    for (count of [7, 8]) { state.n = count; }\n  });\n  window.addEventListener(\"cells-replace\", (event) => {\n    event.detail.old = state;\n    state = { n: 10 };\n    state.n++;\n  });\n  window.addEventListener(\"cells-return\", (event) => {\n    const assigned = (state = { n: 20 });\n    event.detail.same = assigned === state;\n    assigned.n++;\n    event.detail.optionalSame = (optional ??= { n: 1 }) === optional;\n    event.detail.calls = 0;\n    event.detail.skipped = (state ||= (() => { event.detail.calls++; return { n: 99 }; })()) === state;\n  });\n  window.addEventListener(\"cells-throw\", (event) => {\n    try { count++; throw event.detail.error; }\n    catch (error) { event.detail.caught = error; }\n  });\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 171, 171, 182]);
    expect_section(doc.script, [184, 190, 191, 200, 183, 201, 201, 2221, 2221, 2230]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/compound-scope.weiv" {
    const doc = parse("<template><section #for=\"workspace in workspaces\"><div #if=\"workspace.children.length || pendingFor(workspace.id).length\">{{ props.view.locked || props.actions.text(workspace.id) }}</div></section></template>\n<script lang=\"ts\">\nexport let props: { view: { locked: string }, actions: { text: (id: string) => string } };\nlet workspaces = [{ id: \"first\", children: [] }];\nfunction pendingFor(id: string) { return id === \"first\" ? [1] : []; }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 197, 197, 208]);
    expect_section(doc.script, [210, 216, 217, 226, 209, 227, 227, 439, 439, 448]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/conditional-toggle.weiv" {
    const doc = parse("<template>\n  <section class=\"conditional-toggle\">\n    <button @click=\"toggleOpen\">\n      Toggle details\n    </button>\n\n    <p #if=\"open\">Panel is open</p>\n    <p #else>Panel is closed</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n\n  let open = false;\n\n  function toggleOpen() {\n    open = !open;\n  }\n</script>\n\n<style>\n  .conditional-toggle {\n    display: grid;\n    gap: 0.75rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 201, 201, 212]);
    expect_section(doc.script, [215, 221, 222, 231, 214, 232, 232, 359, 359, 368]);
    if doc.style is style {
        expect_section(style, [371, 376, 376, 376, 370, 377, 377, 443, 443, 451]);
    } else {
        assert(false);
    }
}
test "test/examples/basic/dashboard-card.weiv" {
    const doc = parse("<template>\n  <article class=\"dashboard-card\">\n    <MetricBadge :label=\"props.statusLabel\" :tone=\"tone()\" />\n\n    <h3>{{ props.title }}</h3>\n    <p>{{ props.description }}</p>\n\n    <ul class=\"dashboard-card__stats\">\n      <li #for=\"stat in props.stats\">\n        <span>{{ stat.name }}</span>\n        <strong>{{ stat.value }}</strong>\n      </li>\n    </ul>\n\n    <button #if=\"props.actionEnabled\" @click=\"handleOpen\">\n      Open details\n    </button>\n    <p #else>Action unavailable</p>\n  </article>\n</template>\n\n<script lang=\"ts\">\n  import MetricBadge from \"./MetricBadge.weiv\";\n\n  export interface Stat {\n    name: string;\n    value: string;\n  }\n\n  export interface Props {\n    title: string;\n    description: string;\n    statusLabel: string;\n    actionEnabled: boolean;\n    stats: Stat[];\n  }\n\n  export let props: Props;\n\n  function tone() {\n    return props.actionEnabled ? \"ready\" : \"muted\";\n  }\n\n  function handleOpen() {\n    console.log(\"open dashboard details\");\n  }\n</script>\n\n<style>\n  .dashboard-card {\n    display: grid;\n    gap: 1rem;\n    padding: 1rem;\n    border: 1px solid #e4e4e7;\n    border-radius: 24px;\n  }\n\n  .dashboard-card__stats {\n    display: grid;\n    gap: 0.5rem;\n    padding: 0;\n    margin: 0;\n    list-style: none;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 496, 496, 507]);
    expect_section(doc.script, [510, 516, 517, 526, 509, 527, 527, 971, 971, 980]);
    if doc.style is style {
        expect_section(style, [983, 988, 988, 988, 982, 989, 989, 1244, 1244, 1252]);
    } else {
        assert(false);
    }
}
test "test/examples/basic/external-callback.weiv" {
    const doc = parse("<template>\n  <section class=\"external-callback\">\n    <p class=\"count\">{{ count }}</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  let count = 0;\n\n  window.addEventListener(\"weiv-unowned\", () => {\n    count += 1;\n  });\n\n  window.addEventListener(\"weiv-owned\", () => {\n    count += 1;\n  });\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 99, 99, 110]);
    expect_section(doc.script, [113, 119, 120, 129, 112, 130, 130, 292, 292, 301]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/framecept-reactivity.weiv" {
    const doc = parse("<template>\n  <button #for=\"clip in clips\" @click=\"clip.select()\">Select clip</button>\n  <section #if=\"selectedId >= 0\">Selected {{ selectedId }}</section>\n  <section #if=\"selectedId < 0\">No clip selected</section>\n\n  <button @click=\"startThumbnailLoad\">Load thumbnail</button>\n  <img #for=\"asset in media\" :src=\"asset.thumbnailUrl\" alt=\"\" />\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n  export let props: Props;\n\n  let selectedId = -1;\n  let clips = [{ id: 7, select: () => selectClip(7) }];\n  let media = [{ id: 1, thumbnailUrl: \"pending\" }];\n\n  function selectClip(id: number) {\n    selectedId = id;\n  }\n\n  function startThumbnailLoad() {\n    void loadMissingThumbnails();\n  }\n\n  async function loadMissingThumbnails() {\n    const url = await Promise.resolve(\"ready\");\n    media = media.map((asset) => ({ ...asset, thumbnailUrl: url }));\n  }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 342, 342, 353]);
    expect_section(doc.script, [356, 362, 363, 372, 355, 373, 373, 861, 861, 870]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/html-entities.weiv" {
    const doc = parse("<template><p title=\"WORKSPACE &amp; DATA\">WORKSPACE &amp; DATA &#x1F642; &copy; &mdash; &unknown;</p></template>\n<script lang=\"ts\">export let props = {};</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 101, 101, 112]);
    expect_section(doc.script, [114, 120, 121, 130, 113, 131, 131, 153, 153, 162]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/html-void-tags.weiv" {
    const doc = parse("<template><label>Name<input name=\"name\"></label><br><img alt=\"preview\"></template>\n<script lang=\"ts\">export let props = {};</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 71, 71, 82]);
    expect_section(doc.script, [84, 90, 91, 100, 83, 101, 101, 123, 123, 132]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/nested-conditional-list.weiv" {
    const doc = parse("<template>\n  <section style=\"display: block\">\n    <button :class=\"selectedStrategyId\" @click=\"selectThird\">Select third</button>\n    <button @click=\"appendStrategy\">Append fourth</button>\n    <article #for=\"strategy in strategies\" :style=\"strategyStyle(strategy)\">\n      <button @click=\"selectStrategy(strategy.id)\">{{ strategy.title }}</button>\n      <i #if=\"strategy.id === selectedStrategyId\">selected</i>\n    </article>\n    <p>After strategies</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  let strategies = [\n    { id: \"first\", title: \"First\" },\n    { id: \"second\", title: \"Second\" },\n    { id: \"third\", title: \"Third\" },\n  ];\n  let selectedStrategyId = \"second\";\n\n  function strategyStyle(strategy: { id: string }) {\n    return strategy.id === selectedStrategyId ? \"left: 58%; width: 60px\" : \"left: 12%; width: 40px\";\n  }\n\n  function selectStrategy(id: string) {\n    selectedStrategyId = id;\n  }\n\n  function appendStrategy() {\n    strategies = [...strategies, { id: \"fourth\", title: \"Fourth\" }];\n  }\n\n  async function selectThird() {\n    await Promise.resolve();\n    selectedStrategyId = \"third\";\n  }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 465, 465, 476]);
    expect_section(doc.script, [479, 485, 486, 495, 478, 496, 496, 1111, 1111, 1120]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/nested-conditional-parent.weiv" {
    const doc = parse("<template><button @click=\"change\">Change</button><button @click=\"open\">Open</button><button @click=\"close\">Close</button><section #if=\"tabOpen\"><NestedConditionalChild #if=\"available\" :value=\"value\" /></section></template>\n<script lang=\"ts\">\nimport * as NestedConditionalChild from \"./NestedConditionalChild.weiv\";\nlet tabOpen = false;\nlet available = false;\nlet value = 0;\nfunction open() { tabOpen = true; available = true; value = 10; }\nfunction change() { value += 1; }\nfunction close() { tabOpen = false; }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 211, 211, 222]);
    expect_section(doc.script, [224, 230, 231, 240, 223, 241, 241, 512, 512, 521]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/state-contract.weiv" {
    const doc = parse("<template>\n  <p class=\"scalar\">{{ count }}</p>\n  <p class=\"object\">{{ state.count }}</p>\n</template>\n<script lang=\"ts\">\n  let count = 0;\n  const state = { count: 0 };\n\n  window.addEventListener(\"contract-async\", (event) => {\n    event.detail.result = (async () => {\n      count = 1;\n      try {\n        await event.detail.gate;\n      } finally {\n        count = 2;\n      }\n    })();\n  });\n  window.addEventListener(\"contract-detached\", () => {\n    Promise.resolve().then(() => { count = 3; });\n  });\n  window.addEventListener(\"contract-throw\", (event) => {\n    try {\n      count = 4;\n      throw event.detail.error;\n    } catch (error) {\n      event.detail.caught = error;\n    }\n  });\n  window.addEventListener(\"contract-object\", () => {\n    state.count += 1;\n    state.count += 1;\n  });\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 89, 89, 100]);
    expect_section(doc.script, [102, 108, 109, 118, 101, 119, 119, 788, 788, 797]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/static-dynamic-class.weiv" {
    const doc = parse("<template>\n  <button class=\"clip\" :class=\"selected ? 'selected' : ''\" @click=\"toggle\">\n    Toggle selection\n  </button>\n</template>\n\n<script lang=\"ts\">\n  let selected = false;\n\n  function toggle() {\n    selected = !selected;\n  }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 120, 120, 131]);
    expect_section(doc.script, [134, 140, 141, 150, 133, 151, 151, 229, 229, 238]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/svg-namespace.weiv" {
    const doc = parse("<template><button><svg viewBox=\"0 0 10 10\"><path d=\"M0 0L10 10\" /><circle #if=\"visible\" cx=\"5\" cy=\"5\" r=\"2\" /><rect #for=\"item in rects\" width=\"1\" height=\"1\" /><foreignObject><div #if=\"visible\">HTML child</div></foreignObject></svg></button></template>\n<script lang=\"ts\">let visible = true; let rects = [1, 2];</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 241, 241, 252]);
    expect_section(doc.script, [254, 260, 261, 270, 253, 271, 271, 310, 310, 319]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/template-callback-scope.weiv" {
    const doc = parse("<template>\n  <button @click=\"increment\">Increment</button>\n  <p>{{ JSON.stringify(rows.map(({count: local}) => { const next = local + count; return {local, next}; })) }}</p>\n  <p class=\"spread\">{{ Math.max(...values) }}</p>\n  <p class=\"default\">{{ rows.map((value=rows[0])=>value.count+count).join(',') }}</p>\n</template>\n<script lang=\"ts\">\nlet count = 0;\nconst rows = [{count: 4}];\nconst value = 900;\nlet values = [1];\nfunction increment() { count++; values = [values[0] + 1]; }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 310, 310, 321]);
    expect_section(doc.script, [323, 329, 330, 339, 322, 340, 340, 480, 480, 489]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/template-global-shadow.weiv" {
    const doc = parse("<template><p>{{ Math.round(1) }}</p></template>\n<script lang=\"ts\">const Math = { round: (_value: number) => 42 };</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 36, 36, 47]);
    expect_section(doc.script, [49, 55, 56, 65, 48, 66, 66, 113, 113, 122]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/template-globals.weiv" {
    const doc = parse("<template><p>{{ Math.round(zoom * 100) }}%</p><button @click=\"increase\">Zoom</button><input #for=\"item in items\" :value=\"String(item.id)\" /></template>\n<script lang=\"ts\">\nlet zoom = 1;\nlet items = [{ id: 7 }, { id: 8 }];\nfunction increase() { zoom = 1.25; }\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 140, 140, 151]);
    expect_section(doc.script, [153, 159, 160, 169, 152, 170, 170, 258, 258, 267]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/template-prop-parent.weiv" {
    const doc = parse("<template><TemplatePropChild :describedBy=\"`help-${props.id}`\" /></template>\n<script lang=\"ts\">\nimport * as TemplatePropChild from \"./TemplatePropChild.weiv\";\nexport let props: { id: string };\n</script>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 65, 65, 76]);
    expect_section(doc.script, [78, 84, 85, 94, 77, 95, 95, 193, 193, 202]);
    if doc.style is unexpected {
        assert(false);
    }
}
test "test/examples/basic/timer-callback.weiv" {
    const doc = parse("<template>\n  <section class=\"timer-callback\">\n    <p>{{ count }}</p>\n    <button @click=\"schedule\">Schedule</button>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n  export let props: Props;\n\n  let count = 0;\n\n  function schedule() {\n    setTimeout(() => {\n      count += 1;\n    }, 0);\n  }\n</script>\n\n<style>\n  .timer-callback {\n    display: grid;\n    gap: 0.5rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 130, 130, 141]);
    expect_section(doc.script, [144, 150, 151, 160, 143, 161, 161, 316, 316, 325]);
    if doc.style is style {
        expect_section(style, [328, 333, 333, 333, 327, 334, 334, 395, 395, 403]);
    } else {
        assert(false);
    }
}
test "test/examples/basic/todo-list.weiv" {
    const doc = parse("<template>\n  <section class=\"todo-list\">\n    <header class=\"todo-list__header\">\n      <h2>{{ props.title }}</h2>\n      <button @click=\"toggleCompleted\">\n        Toggle completed\n      </button>\n    </header>\n\n    <p #if=\"showCompleted\">Showing completed tasks</p>\n    <p #else>Showing pending tasks</p>\n\n    <ul>\n      <li #for=\"item in visibleItems()\">\n        <span>{{ item.label }}</span>\n      </li>\n    </ul>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface TodoItem {\n    label: string;\n    completed: boolean;\n  }\n\n  export interface Props {\n    title: string;\n  }\n\n  export let props: Props;\n\n  let showCompleted = false;\n  let items: TodoItem[] = [\n    { label: \"Write parser fixtures\", completed: true },\n    { label: \"Implement template binder\", completed: false },\n    { label: \"Test CSS scoping\", completed: false }\n  ];\n\n  function visibleItems() {\n    return items.filter((item) => item.completed === showCompleted);\n  }\n\n  function toggleCompleted() {\n    showCompleted = !showCompleted;\n  }\n</script>\n\n<style>\n  .todo-list {\n    padding: 1rem;\n    border-radius: 20px;\n    background: #fafaf9;\n  }\n\n  .todo-list__header {\n    display: flex;\n    justify-content: space-between;\n    gap: 1rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 427, 427, 438]);
    expect_section(doc.script, [441, 447, 448, 457, 440, 458, 458, 1023, 1023, 1032]);
    if doc.style is style {
        expect_section(style, [1035, 1040, 1040, 1040, 1034, 1041, 1041, 1228, 1228, 1236]);
    } else {
        assert(false);
    }
}
test "test/examples/classic-todo/App.weiv" {
    const doc = parse("<template>\n  <main class=\"todo-app\">\n    <div class=\"todo-app__shell\">\n      <header class=\"todo-app__hero\">\n        <p class=\"todo-app__eyebrow\">Verification Example</p>\n        <div class=\"todo-app__headline\">\n          <h1>{{ props.title }}</h1>\n          <p class=\"todo-app__lede\">Client runtime, nested components, scoped styles, and TS-backed helpers in one polished example.</p>\n        </div>\n        <div class=\"todo-app__summary\">\n          <strong>{{ summary() }}</strong>\n          <span>{{ showCompleted ? \"Viewing completed tasks\" : \"Viewing active tasks\" }}</span>\n        </div>\n      </header>\n\n      <section class=\"todo-app__panel\">\n        <div class=\"todo-app__panel-header\">\n          <div>\n            <p class=\"todo-app__panel-label\">Inbox</p>\n            <h2>Product Todo Board</h2>\n          </div>\n          <button class=\"todo-app__filter\" @click=\"toggleCompletedFilter\">\n            {{ showCompleted ? \"Show active\" : \"Show completed\" }}\n          </button>\n        </div>\n\n        <TodoList\n          :items=\"visibleItems()\"\n          :showCompleted=\"showCompleted\"\n          @toggle=\"toggleItem\"\n        />\n      </section>\n    </div>\n  </main>\n</template>\n\n<script lang=\"ts\">\n  import TodoList from \"./TodoList.weiv\";\n\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export interface Props {\n    title: string;\n  }\n\n  export let props: Props;\n\n  let showCompleted = false;\n  let items: Todo[] = [\n    { id: \"1\", title: \"Ship recursive helper import support\", completed: true },\n    { id: \"2\", title: \"Polish the flagship todo verification app\", completed: false },\n    { id: \"3\", title: \"Tighten DOM event semantics\", completed: false },\n    { id: \"4\", title: \"Document the client preview workflow\", completed: true }\n  ];\n\n  function visibleItems() {\n    return items.filter((item) => item.completed === showCompleted);\n  }\n\n  function summary() {\n    return `${visibleItems().length} ${showCompleted ? \"completed\" : \"active\"} tasks`;\n  }\n\n  function toggleCompletedFilter() {\n    showCompleted = !showCompleted;\n  }\n\n  function toggleItem(itemId: string) {\n    items = items.map((item) =>\n      item.id === itemId ? { ...item, completed: !item.completed } : item\n    );\n  }\n</script>\n\n<style>\n  .todo-app {\n    min-height: 100vh;\n    padding: 2rem 1.25rem 3rem;\n    background:\n      radial-gradient(circle at top left, rgba(247, 201, 72, 0.24), transparent 24rem),\n      linear-gradient(180deg, #f6efe3 0%, #fffaf1 45%, #f7f1e8 100%);\n    color: #1b1208;\n    font-family: \"SF Pro Display\", \"Avenir Next\", \"Segoe UI\", sans-serif;\n  }\n\n  .todo-app__shell {\n    display: grid;\n    gap: 1.5rem;\n    max-width: 52rem;\n    margin: 0 auto;\n  }\n\n  .todo-app__hero {\n    display: grid;\n    gap: 1rem;\n    padding: 1.5rem;\n    border: 1px solid rgba(77, 52, 24, 0.12);\n    border-radius: 28px;\n    background: rgba(255, 251, 245, 0.88);\n    box-shadow: 0 28px 60px rgba(56, 36, 17, 0.08);\n    backdrop-filter: blur(12px);\n  }\n\n  .todo-app__eyebrow {\n    margin: 0;\n    font-size: 0.76rem;\n    font-weight: 700;\n    letter-spacing: 0.18em;\n    text-transform: uppercase;\n    color: #9a6a28;\n  }\n\n  .todo-app__headline {\n    display: grid;\n    gap: 0.65rem;\n  }\n\n  .todo-app__headline h1 {\n    margin: 0;\n    font-size: clamp(2.4rem, 6vw, 4.4rem);\n    line-height: 0.92;\n    letter-spacing: -0.06em;\n  }\n\n  .todo-app__lede {\n    max-width: 38rem;\n    margin: 0;\n    font-size: 1rem;\n    line-height: 1.6;\n    color: #70553a;\n  }\n\n  .todo-app__summary {\n    display: flex;\n    flex-wrap: wrap;\n    gap: 0.75rem;\n    align-items: center;\n  }\n\n  .todo-app__summary strong,\n  .todo-app__summary span {\n    padding: 0.7rem 1rem;\n    border-radius: 999px;\n    background: #fffdf8;\n    border: 1px solid rgba(112, 85, 58, 0.16);\n  }\n\n  .todo-app__summary strong {\n    font-size: 1rem;\n  }\n\n  .todo-app__summary span {\n    font-size: 0.92rem;\n    color: #6e5743;\n  }\n\n  .todo-app__panel {\n    display: grid;\n    gap: 1.25rem;\n    padding: 1.4rem;\n    border-radius: 30px;\n    background: #fffdf9;\n    border: 1px solid rgba(77, 52, 24, 0.12);\n    box-shadow: 0 24px 48px rgba(56, 36, 17, 0.08);\n  }\n\n  .todo-app__panel-header {\n    display: flex;\n    flex-wrap: wrap;\n    gap: 1rem;\n    align-items: end;\n    justify-content: space-between;\n  }\n\n  .todo-app__panel-label {\n    margin: 0 0 0.35rem;\n    font-size: 0.78rem;\n    font-weight: 700;\n    letter-spacing: 0.14em;\n    text-transform: uppercase;\n    color: #9a6a28;\n  }\n\n  .todo-app__panel-header h2 {\n    margin: 0;\n    font-size: 1.45rem;\n    letter-spacing: -0.04em;\n  }\n\n  .todo-app__filter {\n    padding: 0.9rem 1.2rem;\n    border: 0;\n    border-radius: 999px;\n    background: linear-gradient(135deg, #1e1b16 0%, #50331e 100%);\n    color: #fff8ef;\n    font: inherit;\n    font-weight: 700;\n    cursor: pointer;\n    box-shadow: 0 14px 30px rgba(43, 27, 14, 0.2);\n  }\n\n  .todo-app__filter:active {\n    transform: translateY(1px);\n  }\n\n  @media (max-width: 640px) {\n    .todo-app {\n      padding-inline: 0.9rem;\n    }\n\n    .todo-app__hero,\n    .todo-app__panel {\n      padding: 1.1rem;\n      border-radius: 24px;\n    }\n\n    .todo-app__summary {\n      display: grid;\n    }\n\n    .todo-app__filter {\n      width: 100%;\n      justify-content: center;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1176, 1176, 1187]);
    expect_section(doc.script, [1190, 1196, 1197, 1206, 1189, 1207, 1207, 2252, 2252, 2261]);
    if doc.style is style {
        expect_section(style, [2264, 2269, 2269, 2269, 2263, 2270, 2270, 5274, 5274, 5282]);
    } else {
        assert(false);
    }
}
test "test/examples/classic-todo/TodoItem.weiv" {
    const doc = parse("<template>\n  <article class=\"todo-item\">\n    <label class=\"todo-item__label\">\n      <input :checked=\"props.item.completed\" @change=\"emit('toggle', props.item.id)\" type=\"checkbox\" />\n      <span class=\"todo-item__copy\">\n        <strong>{{ props.item.title }}</strong>\n        <em>{{ props.item.completed ? \"Completed\" : \"In progress\" }}</em>\n      </span>\n    </label>\n  </article>\n</template>\n\n<script lang=\"ts\">\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export interface Props {\n    item: Todo;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .todo-item {\n    display: flex;\n    align-items: center;\n    padding: 0.95rem 1rem;\n    border: 1px solid rgba(77, 52, 24, 0.12);\n    border-radius: 22px;\n    background: linear-gradient(180deg, #fffefb 0%, #fff8ef 100%);\n    box-shadow: 0 14px 30px rgba(56, 36, 17, 0.06);\n  }\n\n  .todo-item__label {\n    display: flex;\n    align-items: center;\n    gap: 0.9rem;\n    width: 100%;\n    cursor: pointer;\n  }\n\n  .todo-item__label input {\n    width: 1.2rem;\n    height: 1.2rem;\n    margin: 0;\n    accent-color: #1f7a45;\n    flex: none;\n  }\n\n  .todo-item__copy {\n    display: grid;\n    gap: 0.18rem;\n  }\n\n  .todo-item__copy strong {\n    font-size: 1rem;\n    font-weight: 700;\n    color: #20140b;\n  }\n\n  .todo-item__copy em {\n    font-style: normal;\n    font-size: 0.84rem;\n    color: #7b6652;\n  }\n\n  .todo-item__label input:checked + .todo-item__copy strong {\n    text-decoration: line-through;\n    text-decoration-thickness: 2px;\n    color: #7b6652;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 381, 381, 392]);
    expect_section(doc.script, [395, 401, 402, 411, 394, 412, 412, 578, 578, 587]);
    if doc.style is style {
        expect_section(style, [590, 595, 595, 595, 589, 596, 596, 1547, 1547, 1555]);
    } else {
        assert(false);
    }
}
test "test/examples/classic-todo/TodoList.weiv" {
    const doc = parse("<template>\n  <section class=\"todo-list\">\n    <div #if=\"props.items.length === 0\" class=\"todo-list__empty\">\n      <p class=\"todo-list__empty-title\">Nothing in this lane yet</p>\n      <span class=\"todo-list__empty-copy\">{{ props.showCompleted ? \"Completed work will land here.\" : \"Active work will land here.\" }}</span>\n    </div>\n    <ul #else class=\"todo-list__items\">\n      <li #for=\"item in props.items\">\n        <TodoItem :item=\"item\" @toggle=\"emitToggle\" />\n      </li>\n    </ul>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import TodoItem from \"./TodoItem.weiv\";\n\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export interface Props {\n    items: Todo[];\n    showCompleted: boolean;\n  }\n\n  export let props: Props;\n\n  function emitToggle(itemId: string) {\n    emit(\"toggle\", itemId);\n  }\n</script>\n\n<style>\n  .todo-list {\n    display: grid;\n    gap: 1rem;\n  }\n\n  .todo-list__empty {\n    display: grid;\n    gap: 0.45rem;\n    padding: 1.25rem;\n    border: 1px dashed rgba(154, 106, 40, 0.26);\n    border-radius: 22px;\n    background: linear-gradient(180deg, rgba(250, 241, 225, 0.7), rgba(255, 253, 248, 0.92));\n  }\n\n  .todo-list__empty-title {\n    margin: 0;\n    font-size: 1rem;\n    font-weight: 700;\n    color: #2d1d10;\n  }\n\n  .todo-list__empty-copy {\n    font-size: 0.94rem;\n    line-height: 1.5;\n    color: #725741;\n  }\n\n  .todo-list__items {\n    display: grid;\n    gap: 0.85rem;\n    padding: 0;\n    margin: 0;\n    list-style: none;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 497, 497, 508]);
    expect_section(doc.script, [511, 517, 518, 527, 510, 528, 528, 841, 841, 850]);
    if doc.style is style {
        expect_section(style, [853, 858, 858, 858, 852, 859, 859, 1493, 1493, 1501]);
    } else {
        assert(false);
    }
}
test "test/examples/imported-helper/App.weiv" {
    const doc = parse("<template>\n  <section class=\"imported-helper\">\n    <h1>{{ headline() }}</h1>\n    <p>{{ props.count }}</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { formatTitle } from \"./format.js\";\n\n  export interface Props {\n    title: string;\n    count: number;\n  }\n\n  export let props: Props;\n\n  function headline() {\n    return formatTitle(props.title);\n  }\n</script>\n\n<style>\n  .imported-helper {\n    display: grid;\n    gap: 0.5rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 119, 119, 130]);
    expect_section(doc.script, [133, 139, 140, 149, 132, 150, 150, 360, 360, 369]);
    if doc.style is style {
        expect_section(style, [372, 377, 377, 377, 371, 378, 378, 440, 440, 448]);
    } else {
        assert(false);
    }
}
test "test/examples/imported-ts-helper/App.weiv" {
    const doc = parse("<template>\n  <section class=\"imported-ts-helper\">\n    <h1>{{ headline() }}</h1>\n    <p>{{ props.count }}</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import { formatTitle } from \"./format.ts\";\n\n  export interface Props {\n    title: string;\n    count: number;\n  }\n\n  export let props: Props;\n\n  function headline() {\n    return formatTitle(props.title);\n  }\n</script>\n\n<style>\n  .imported-ts-helper {\n    display: grid;\n    gap: 0.5rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 122, 122, 133]);
    expect_section(doc.script, [136, 142, 143, 152, 135, 153, 153, 363, 363, 372]);
    if doc.style is style {
        expect_section(style, [375, 380, 380, 380, 374, 381, 381, 446, 446, 454]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/App.weiv" {
    const doc = parse("<template>\n  <WorkspaceShell :collapsed=\"shellState.collapsed\">\n    <template slot:header>\n      <WorkspaceHeader\n        :collapsed=\"shellState.collapsed\"\n        :notifications=\"workspaceShared.notifications\"\n        :sectionLabel=\"currentSectionLabel()\"\n        :subtitle=\"headerSubtitle()\"\n        :title=\"headerTitle()\"\n        @clear-notifications=\"clearHeaderNotifications\"\n        @open-notifications=\"openNotifications\"\n        @queue-refresh=\"queueRefresh\"\n        @toggle-sidebar=\"toggleSidebar\"\n      />\n    </template>\n\n    <template slot:toolbar>\n      <div class=\"project-health\">\n        <div class=\"project-health__label\">\n          <strong>{{ projectLabel() }}</strong>\n          <small>{{ projectIssues().length }} issues in scope</small>\n        </div>\n        <div class=\"project-health__stats\">\n          <span class=\"project-health__chip project-health__chip--open\">Open {{ projectOpenCount() }}</span>\n          <span class=\"project-health__chip project-health__chip--review\">Review {{ projectReviewCount() }}</span>\n          <span class=\"project-health__chip project-health__chip--done\">Done {{ projectDoneCount() }}</span>\n        </div>\n      </div>\n    </template>\n\n    <template slot:sidebar>\n      <WorkspaceSidebar\n        :collapsed=\"shellState.collapsed\"\n        :currentPath=\"workspaceShared.currentPath\"\n        :currentWorkspaceId=\"workspaceShared.currentWorkspaceId\"\n        :selectedProjectId=\"workspaceShared.selectedProjectId\"\n        :statusMessage=\"shellState.statusMessage\"\n        @navigate=\"handleNavigate\"\n        @switch-project=\"switchProject\"\n        @switch-workspace=\"switchWorkspace\"\n      />\n    </template>\n\n    <div class=\"kanib-app__route-root\">\n      <div id=\"workspace-route-root\">{{ ensureRouter() }}</div>\n    </div>\n\n    <template slot:detail>\n      <DetailPanel\n        :externalTicks=\"externalTicks\"\n        :liveSyncConnected=\"externalWatchRegistered\"\n        :item=\"selectedIssue()\"\n        :recentEvents=\"recentEvents\"\n        :workspaceId=\"workspaceShared.currentWorkspaceId\"\n        @advance-issue=\"advanceSelectedIssue\"\n        @open-issue=\"openSelectedIssue\"\n        @register-external-watch=\"registerExternalWatch\"\n        @trigger-external-pulse=\"triggerExternalPulse\"\n      />\n    </template>\n  </WorkspaceShell>\n</template>\n\n<script lang=\"ts\">\n  import { createRouter } from \"weiv:router\";\n  import IssueListPage from \"./views/IssueListPage.weiv\";\n  import OverviewPage from \"./views/OverviewPage.weiv\";\n  import DetailPanel from \"./components/DetailPanel.weiv\";\n  import IssueBoardPage from \"./views/IssueBoardPage.weiv\";\n  import IssueDetailPage from \"./views/IssueDetailPage.weiv\";\n  import NotificationsPage from \"./views/NotificationsPage.weiv\";\n  import MembersPage from \"./views/MembersPage.weiv\";\n  import SettingsPage from \"./views/SettingsPage.weiv\";\n  import WorkspaceHeader from \"./components/WorkspaceHeader.weiv\";\n  import WorkspaceShell from \"./components/WorkspaceShell.weiv\";\n  import WorkspaceSidebar from \"./components/WorkspaceSidebar.weiv\";\n  import {\n    boardRoute,\n    bumpNotifications,\n    clearNotifications,\n    cycleIssueStatus,\n    emitExternalSavePulse,\n    findIssue,\n    findProject,\n    findWorkspace,\n    issuesRoute,\n    issueRoute,\n    listIssues,\n    navigateTo,\n    notificationsRoute,\n    registerExternalSaveListener,\n    setCurrentWorkspaceId,\n    setSelectedProjectId,\n    setWorkspaceRouter,\n    syncRouteState,\n    workspaceRoute,\n    workspaceShared\n  } from \"./state/workspace.ts\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let routerReady = false;\n  let routerBootstrapQueued = false;\n  let externalTicks = 0;\n  let externalWatchRegistered = false;\n  let recentEvents = [\n    \"Workspace opened. Team activity stream is online.\"\n  ];\n  let shellState = {\n    collapsed: false,\n    statusMessage: \"Track issues, board movement, and team updates from one workspace.\"\n  };\n\n  function pushRecentEvent(message: string) {\n    recentEvents = [message, ...recentEvents].slice(0, 6);\n  }\n\n  function headerTitle() {\n    const workspace = findWorkspace(workspaceShared.currentWorkspaceId);\n    return workspace ? workspace.name : \"Workspace\";\n  }\n\n  function headerSubtitle() {\n    const workspace = findWorkspace(workspaceShared.currentWorkspaceId);\n    const project = findProject(workspaceShared.selectedProjectId);\n    if (!workspace) {\n      return shellState.statusMessage;\n    }\n    const projectLabel = project ? `${project.name}` : \"All projects\";\n    return `${workspace.openCount} open issues · ${workspace.issueCount} total · ${projectLabel} · ${shellState.statusMessage}`;\n  }\n\n  function currentSectionLabel() {\n    const path = workspaceShared.currentPath;\n    if (path.indexOf(\"/issues/\") !== -1) return \"Issue detail\";\n    if (path.endsWith(\"/issues\")) return \"Issue list\";\n    if (path.endsWith(\"/board\")) return \"Board\";\n    if (path.endsWith(\"/notifications\")) return \"Notifications\";\n    if (path.endsWith(\"/members\")) return \"Members\";\n    if (path.endsWith(\"/settings\")) return \"Settings\";\n    return \"Overview\";\n  }\n\n  function selectedIssue() {\n    const selected = findIssue(workspaceShared.selectedIssueId);\n    if (selected && selected.workspaceId === workspaceShared.currentWorkspaceId) {\n      return selected;\n    }\n    const workspaceIssues = listIssues(workspaceShared.currentWorkspaceId, workspaceShared.selectedProjectId);\n    return workspaceIssues.length > 0 ? workspaceIssues[0] : null;\n  }\n\n  function projectLabel() {\n    const project = findProject(workspaceShared.selectedProjectId);\n    return project ? `${project.key} · ${project.name}` : \"All projects\";\n  }\n\n  function projectIssues() {\n    workspaceShared.saveTick;\n    return listIssues(workspaceShared.currentWorkspaceId, workspaceShared.selectedProjectId);\n  }\n\n  function projectOpenCount() {\n    return projectIssues().filter((issue) => issue.status !== \"done\").length;\n  }\n\n  function projectReviewCount() {\n    return projectIssues().filter((issue) => issue.status === \"review\").length;\n  }\n\n  function projectDoneCount() {\n    return projectIssues().filter((issue) => issue.status === \"done\").length;\n  }\n\n  function toggleSidebar() {\n    shellState.collapsed = !shellState.collapsed;\n    shellState.statusMessage = shellState.collapsed\n      ? \"Compact navigation enabled.\"\n      : \"Navigation expanded.\";\n  }\n\n  function clearHeaderNotifications() {\n    clearNotifications();\n    shellState.statusMessage = \"Notifications cleared.\";\n    pushRecentEvent(\"Notifications cleared by workspace owner.\");\n  }\n\n  function queueRefresh() {\n    shellState.statusMessage = \"Syncing updates.\";\n    queueMicrotask(() => {\n      bumpNotifications();\n      shellState.statusMessage = \"Updates synced.\";\n      pushRecentEvent(\"Updates synced from live sources.\");\n    });\n  }\n\n  function handleNavigate(path: string) {\n    navigateTo(path);\n  }\n\n  function openNotifications() {\n    navigateTo(notificationsRoute(workspaceShared.currentWorkspaceId));\n  }\n\n  function switchWorkspace(workspaceId: string) {\n    setCurrentWorkspaceId(workspaceId);\n    navigateTo(workspaceRoute(workspaceId));\n  }\n\n  function switchProject(projectId: string) {\n    setSelectedProjectId(projectId);\n    syncRouteState(workspaceShared.currentPath, workspaceShared.currentWorkspaceId);\n    if (workspaceShared.currentPath.indexOf(\"/issues/\") !== -1) {\n      navigateTo(issuesRoute(workspaceShared.currentWorkspaceId));\n    }\n  }\n\n  function openSelectedIssue() {\n    const issue = selectedIssue();\n    if (!issue) {\n      return;\n    }\n    navigateTo(issueRoute(issue.workspaceId, issue.id));\n  }\n\n  function advanceSelectedIssue(issueId: string) {\n    cycleIssueStatus(issueId);\n    shellState.statusMessage = \"Issue status advanced.\";\n    pushRecentEvent(`Issue ${issueId} status moved forward.`);\n  }\n\n  function registerExternalWatch() {\n    if (externalWatchRegistered) {\n      shellState.statusMessage = \"External save listener already connected.\";\n      return;\n    }\n    externalWatchRegistered = true;\n    registerExternalSaveListener(() => {\n      externalTicks += 1;\n      shellState.statusMessage = \"External save signal received.\";\n      const issue = selectedIssue();\n      const issueLabel = issue ? issue.id : \"current issue\";\n      pushRecentEvent(`Teammate update synced for ${issueLabel}.`);\n    });\n    shellState.statusMessage = \"Live sync connected.\";\n    pushRecentEvent(\"Live sync connected for teammate updates.\");\n  }\n\n  function triggerExternalPulse() {\n    emitExternalSavePulse();\n  }\n\n  function routeStatusMessage(path: string) {\n    if (path.indexOf(\"/issues/\") !== -1) return \"Review the issue details and move status forward.\";\n    if (path.endsWith(\"/issues\")) return \"Filter the issue list and open the next item.\";\n    if (path.endsWith(\"/board\")) return \"Watch work move between backlog, progress, review, and done.\";\n    if (path.endsWith(\"/notifications\")) return \"Review personal mentions and recent workspace updates.\";\n    if (path.endsWith(\"/members\")) return \"Keep team roles and ownership visible.\";\n    if (path.endsWith(\"/settings\")) return \"Change workspace behavior without leaving the app shell.\";\n    return \"Overview keeps the workspace signal clear.\";\n  }\n\n  function ensureRouter() {\n    if (routerReady || typeof document === \"undefined\") {\n      return \"\";\n    }\n\n    const routeTarget = document.getElementById(\"workspace-route-root\");\n    if (!routeTarget) {\n      if (!routerBootstrapQueued) {\n        routerBootstrapQueued = true;\n        queueMicrotask(() => {\n          routerBootstrapQueued = false;\n          ensureRouter();\n        });\n      }\n      return \"\";\n    }\n\n    const router = createRouter({\n      mode: \"history\",\n      routes: [\n        {\n          path: \"/\",\n          component: () => OverviewPage,\n          props: () => ({ workspaceId: workspaceShared.currentWorkspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId\",\n          component: () => OverviewPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId/issues\",\n          component: () => IssueListPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId/board\",\n          component: () => IssueBoardPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId/issues/:issueId\",\n          component: () => IssueDetailPage,\n          props: (route) => ({\n            workspaceId: route.params.workspaceId,\n            issueId: route.params.issueId\n          })\n        },\n        {\n          path: \"/workspaces/:workspaceId/members\",\n          component: () => MembersPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId/notifications\",\n          component: () => NotificationsPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        },\n        {\n          path: \"/workspaces/:workspaceId/settings\",\n          component: () => SettingsPage,\n          props: (route) => ({ workspaceId: route.params.workspaceId })\n        }\n      ],\n      target: routeTarget\n    });\n\n    setWorkspaceRouter(router);\n    router.afterEach(({ to }) => {\n      syncRouteState(to.path, to.params.workspaceId, to.params.issueId);\n      shellState.statusMessage = routeStatusMessage(to.path);\n    });\n\n    routerReady = true;\n\n    const issue = selectedIssue();\n    if (!issue && listIssues(workspaceShared.currentWorkspaceId, workspaceShared.selectedProjectId).length > 0) {\n      const firstIssue = listIssues(workspaceShared.currentWorkspaceId, workspaceShared.selectedProjectId)[0];\n      syncRouteState(workspaceShared.currentPath, workspaceShared.currentWorkspaceId, firstIssue.id);\n    }\n    return \"\";\n  }\n</script>\n\n<style>\n  .project-health {\n    display: flex;\n    align-items: center;\n    justify-content: space-between;\n    gap: 0.75rem;\n    padding: 0.75rem 1rem;\n    border: 1px solid #d7e0e8;\n    border-radius: 16px;\n    background: rgba(255, 255, 255, 0.9);\n    box-shadow: 0 10px 24px rgba(24, 44, 66, 0.08);\n  }\n\n  .project-health__label {\n    display: grid;\n    gap: 0.15rem;\n  }\n\n  .project-health__label small {\n    color: #66788f;\n  }\n\n  .project-health__stats {\n    display: flex;\n    flex-wrap: wrap;\n    gap: 0.45rem;\n  }\n\n  .project-health__chip {\n    padding: 0.35rem 0.6rem;\n    border-radius: 999px;\n    font-size: 0.82rem;\n    border: 1px solid transparent;\n  }\n\n  .project-health__chip--open {\n    background: #eef4fb;\n    color: #264766;\n    border-color: #d4e2f2;\n  }\n\n  .project-health__chip--review {\n    background: #fff3e8;\n    color: #80522f;\n    border-color: #f5dec8;\n  }\n\n  .project-health__chip--done {\n    background: #eaf7ef;\n    color: #2f6a48;\n    border-color: #cfe8d8;\n  }\n\n  .kanib-app__route-root {\n    min-height: 100%;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 2287, 2287, 2298]);
    expect_section(doc.script, [2301, 2307, 2308, 2317, 2300, 2318, 2318, 11920, 11920, 11929]);
    if doc.style is style {
        expect_section(style, [11932, 11937, 11937, 11937, 11931, 11938, 11938, 12983, 12983, 12991]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/ActivityItem.weiv" {
    const doc = parse("<template>\n  <li :class=\"itemClass()\">\n    <button class=\"activity-item__content\" @click=\"openIssue\">\n      <strong>{{ props.title }}</strong>\n      <p>{{ props.summary }}</p>\n      <small>{{ props.owner }} · {{ props.status }} · {{ props.priority }}</small>\n    </button>\n    <button class=\"activity-item__action\" @click=\"openIssue\">Open</button>\n  </li>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    id: string;\n    title: string;\n    summary: string;\n    owner: string;\n    status: string;\n    priority: string;\n    selected: boolean;\n  }\n\n  export let props: Props;\n\n  function itemClass() {\n    if (props.selected) {\n      return \"activity-item activity-item--selected\";\n    }\n    return \"activity-item\";\n  }\n\n  function openIssue() {\n    emit(\"open-issue\", props.id);\n  }\n</script>\n\n<style>\n  .activity-item {\n    display: grid;\n    grid-template-columns: minmax(0, 1fr) auto;\n    gap: 0.75rem;\n    padding: 0.9rem 0;\n    border-top: 1px solid #edf2f6;\n  }\n\n  .activity-item:first-child {\n    border-top: none;\n  }\n\n  .activity-item--selected {\n    color: #0c2138;\n  }\n\n  .activity-item__content,\n  .activity-item__action {\n    font: inherit;\n  }\n\n  .activity-item__content {\n    border: none;\n    background: none;\n    text-align: left;\n    padding: 0;\n    cursor: pointer;\n  }\n\n  .activity-item__action {\n    align-self: start;\n    border: 1px solid #dbe4ec;\n    border-radius: 999px;\n    padding: 0.45rem 0.7rem;\n    background: #fff;\n    cursor: pointer;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 358, 358, 369]);
    expect_section(doc.script, [372, 378, 379, 388, 371, 389, 389, 797, 797, 806]);
    if doc.style is style {
        expect_section(style, [809, 814, 814, 814, 808, 815, 815, 1488, 1488, 1496]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/DetailPanel.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <template slot:header>\n      <div>\n        <h2>Selected issue</h2>\n        <p class=\"detail-panel__subhead\">Quick actions and live team sync stay visible across routes.</p>\n      </div>\n    </template>\n\n    <template slot:actions>\n      <button class=\"detail-panel__ghost\" :disabled=\"props.liveSyncConnected\" @click=\"registerWatch\">\n        {{ props.liveSyncConnected ? \"Live sync connected\" : \"Start live sync\" }}\n      </button>\n      <button class=\"detail-panel__ghost\" @click=\"triggerExternalPulse\">Simulate teammate update</button>\n    </template>\n\n    <EmptyState #if=\"!props.item\">\n      <template slot:message>\n        <p>No issue is selected yet.</p>\n      </template>\n      <p>Open any issue from the list or board to keep the side panel in sync.</p>\n    </EmptyState>\n\n    <section #else class=\"detail-panel__content\">\n      <header class=\"detail-panel__headline\">\n        <strong>{{ props.item.title }}</strong>\n        <span>{{ props.item.status }}</span>\n      </header>\n\n      <DetailSection :body=\"props.item.summary\" :title=\"'Summary'\" />\n      <DetailSection :body=\"props.item.detail\" :title=\"'Detail'\" />\n\n      <footer class=\"detail-panel__footer\">\n        <p class=\"detail-panel__ticks\">Live teammate updates: {{ props.externalTicks }}</p>\n        <div class=\"detail-panel__actions\">\n          <button class=\"detail-panel__ghost\" @click=\"openIssue\">Open detail</button>\n          <button class=\"detail-panel__primary\" @click=\"advanceIssue\">Advance status</button>\n        </div>\n      </footer>\n\n      <ul class=\"detail-panel__activity\">\n        <li #for=\"event in props.recentEvents\">{{ event }}</li>\n      </ul>\n    </section>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import DetailSection from \"./DetailSection.weiv\";\n  import EmptyState from \"./EmptyState.weiv\";\n  import Panel from \"./Panel.weiv\";\n\n  export interface DetailItem {\n    id: string;\n    title: string;\n    summary: string;\n    detail: string;\n    status: string;\n  }\n\n  export interface Props {\n    item: DetailItem | null;\n    workspaceId: string;\n    externalTicks: number;\n    liveSyncConnected: boolean;\n    recentEvents: string[];\n  }\n\n  export let props: Props;\n\n  function openIssue() {\n    if (!props.item) {\n      return;\n    }\n    emit(\"open-issue\", props.item.id);\n  }\n\n  function advanceIssue() {\n    if (!props.item) {\n      return;\n    }\n    emit(\"advance-issue\", props.item.id);\n  }\n\n  function registerWatch() {\n    emit(\"register-external-watch\", null);\n  }\n\n  function triggerExternalPulse() {\n    emit(\"trigger-external-pulse\", null);\n  }\n</script>\n\n<style>\n  .detail-panel__subhead,\n  .detail-panel__ticks {\n    color: #6b7a8d;\n  }\n\n  .detail-panel__content {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .detail-panel__activity {\n    margin: 0;\n    padding: 0;\n    list-style: none;\n    display: grid;\n    gap: 0.45rem;\n    border-top: 1px solid #edf2f6;\n    padding-top: 0.7rem;\n    color: #42556c;\n  }\n\n  .detail-panel__headline,\n  .detail-panel__footer {\n    display: flex;\n    align-items: center;\n    justify-content: space-between;\n    gap: 1rem;\n  }\n\n  .detail-panel__actions {\n    display: flex;\n    gap: 0.6rem;\n  }\n\n  .detail-panel__ghost,\n  .detail-panel__primary {\n    border-radius: 999px;\n    padding: 0.55rem 0.85rem;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .detail-panel__ghost {\n    border: 1px solid #dbe4ec;\n    background: #fff;\n  }\n\n  .detail-panel__primary {\n    border: none;\n    background: #182c42;\n    color: #fff;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1686, 1686, 1697]);
    expect_section(doc.script, [1700, 1706, 1707, 1716, 1699, 1717, 1717, 2576, 2576, 2585]);
    if doc.style is style {
        expect_section(style, [2588, 2593, 2593, 2593, 2587, 2594, 2594, 3490, 3490, 3498]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/DetailSection.weiv" {
    const doc = parse("<template>\n  <section class=\"detail-section\">\n    <h3>{{ props.title }}</h3>\n    <p>{{ props.body }}</p>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    title: string;\n    body: string;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .detail-section {\n    display: grid;\n    gap: 0.45rem;\n    padding: 0.85rem 0;\n    border-top: 1px solid #edf2f6;\n  }\n\n  .detail-section:first-child {\n    border-top: none;\n    padding-top: 0;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 118, 118, 129]);
    expect_section(doc.script, [132, 138, 139, 148, 131, 149, 149, 246, 246, 255]);
    if doc.style is style {
        expect_section(style, [258, 263, 263, 263, 257, 264, 264, 464, 464, 472]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/EmptyState.weiv" {
    const doc = parse("<template>\n  <section class=\"empty-state\">\n    <div class=\"empty-state__icon\">\n      <slot name=\"icon\"></slot>\n    </div>\n    <header class=\"empty-state__header\">\n      <slot name=\"message\">\n        <p class=\"empty-state__fallback-message\">Nothing is selected yet.</p>\n      </slot>\n    </header>\n    <div class=\"empty-state__body\">\n      <slot>\n        <p class=\"empty-state__fallback-body\">Choose a route or record to keep the workspace moving.</p>\n      </slot>\n    </div>\n    <footer class=\"empty-state__actions\">\n      <slot name=\"actions\"></slot>\n    </footer>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .empty-state {\n    border: 1px dashed #c7d1db;\n    border-radius: 16px;\n    padding: 1rem;\n    background: #f8fbff;\n  }\n\n  .empty-state__icon:empty,\n  .empty-state__actions:empty {\n    display: none;\n  }\n\n  .empty-state__actions {\n    margin-top: 0.85rem;\n  }\n\n  .empty-state__fallback-message,\n  .empty-state__fallback-body {\n    color: #6d7b8d;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 580, 580, 591]);
    expect_section(doc.script, [594, 600, 601, 610, 593, 611, 611, 668, 668, 677]);
    if doc.style is style {
        expect_section(style, [680, 685, 685, 685, 679, 686, 686, 1040, 1040, 1048]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/MetricCard.weiv" {
    const doc = parse("<template>\n  <article :class=\"cardClass()\">\n    <p class=\"metric-card__label\">{{ props.label }}</p>\n    <strong class=\"metric-card__value\">{{ props.value }}</strong>\n    <p class=\"metric-card__change\">{{ props.change > 0 ? \"+\" : \"\" }}{{ props.change }}%</p>\n  </article>\n</template>\n\n<script lang=\"ts\">\n  import { metricToneClass } from \"../utils/metric_tone.js\";\n\n  export interface Props {\n    label: string;\n    value: string;\n    change: number;\n  }\n\n  export let props: Props;\n\n  function cardClass() {\n    return `metric-card ${metricToneClass(props.change)}`;\n  }\n</script>\n\n<style>\n  .metric-card {\n    display: grid;\n    gap: 0.35rem;\n    padding: 1rem;\n    border-radius: 18px;\n    background: #f6f9fc;\n  }\n\n  .metric-card__label,\n  .metric-card__change {\n    color: #697a90;\n  }\n\n  .metric-card__value {\n    font-size: 1.8rem;\n  }\n\n  .metric-card--up {\n    box-shadow: inset 0 0 0 1px rgba(43, 148, 101, 0.18);\n  }\n\n  .metric-card--down {\n    box-shadow: inset 0 0 0 1px rgba(196, 83, 74, 0.18);\n  }\n\n  .metric-card--flat {\n    box-shadow: inset 0 0 0 1px rgba(108, 124, 145, 0.18);\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 271, 271, 282]);
    expect_section(doc.script, [285, 291, 292, 301, 284, 302, 302, 571, 571, 580]);
    if doc.style is style {
        expect_section(style, [583, 588, 588, 588, 582, 589, 589, 1098, 1098, 1106]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/MetricGrid.weiv" {
    const doc = parse("<template>\n  <div class=\"metric-grid\">\n    <MetricCard #for=\"metric in props.metrics\" :change=\"metric.change\" :label=\"metric.label\" :value=\"metric.value\" />\n  </div>\n</template>\n\n<script lang=\"ts\">\n  import MetricCard from \"./MetricCard.weiv\";\n\n  export interface Metric {\n    id: string;\n    label: string;\n    value: string;\n    change: number;\n  }\n\n  export interface Props {\n    metrics: Metric[];\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .metric-grid {\n    display: grid;\n    grid-template-columns: repeat(3, minmax(0, 1fr));\n    gap: 0.75rem;\n  }\n\n  @media (max-width: 760px) {\n    .metric-grid {\n      grid-template-columns: 1fr;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 166, 166, 177]);
    expect_section(doc.script, [180, 186, 187, 196, 179, 197, 197, 434, 434, 443]);
    if doc.style is style {
        expect_section(style, [446, 451, 451, 451, 445, 452, 452, 659, 659, 667]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/Panel.weiv" {
    const doc = parse("<template>\n  <section class=\"panel\">\n    <header class=\"panel__header\">\n      <div class=\"panel__heading\">\n        <slot name=\"header\">\n          <h2 class=\"panel__fallback-title\">Untitled panel</h2>\n        </slot>\n      </div>\n      <div class=\"panel__actions\">\n        <slot name=\"actions\"></slot>\n      </div>\n    </header>\n    <div class=\"panel__body\">\n      <slot>\n        <p class=\"panel__fallback-body\">No content yet.</p>\n      </slot>\n    </div>\n    <footer class=\"panel__footer\">\n      <slot name=\"footer\"></slot>\n    </footer>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .panel {\n    border: 1px solid #d7e0e8;\n    border-radius: 18px;\n    background: linear-gradient(180deg, #ffffff 0%, #fdfefe 100%);\n    box-shadow: 0 14px 34px rgba(24, 44, 66, 0.08);\n    transition: box-shadow 180ms ease, border-color 180ms ease;\n  }\n\n  .panel:hover {\n    border-color: #cfdbe7;\n    box-shadow: 0 18px 42px rgba(24, 44, 66, 0.12);\n  }\n\n  .panel__header {\n    display: flex;\n    align-items: start;\n    justify-content: space-between;\n    gap: 1rem;\n    padding: 1rem 1rem 0.75rem;\n  }\n\n  .panel__body {\n    padding: 0 1rem 1rem;\n  }\n\n  .panel__footer:empty {\n    display: none;\n  }\n\n  .panel__footer {\n    padding: 0 1rem 1rem;\n  }\n\n  .panel__fallback-title,\n  .panel__fallback-body {\n    color: #66758a;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 552, 552, 563]);
    expect_section(doc.script, [566, 572, 573, 582, 565, 583, 583, 640, 640, 649]);
    if doc.style is style {
        expect_section(style, [652, 657, 657, 657, 651, 658, 658, 1388, 1388, 1396]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/WorkspaceHeader.weiv" {
    const doc = parse("<template>\n  <div class=\"workspace-header\">\n    <div>\n      <p class=\"workspace-header__eyebrow\">Kaneo-inspired verification app</p>\n      <h1>{{ props.title }}</h1>\n      <p class=\"workspace-header__subtitle\">{{ props.subtitle }}</p>\n    </div>\n\n    <div class=\"workspace-header__actions\">\n      <span class=\"workspace-header__section\">{{ props.sectionLabel }}</span>\n      <button class=\"workspace-header__ghost\" @click=\"handleOpenNotifications\">Open notifications</button>\n      <button class=\"workspace-header__ghost\" @click=\"handleQueueRefresh\">Sync updates</button>\n      <button class=\"workspace-header__ghost\" @click=\"handleClearNotifications\">Clear notifications</button>\n      <button class=\"workspace-header__primary\" @click=\"handleToggleSidebar\">\n        {{ props.collapsed ? \"Expand sidebar\" : \"Collapse sidebar\" }}\n      </button>\n      <span class=\"workspace-header__notification\">{{ props.notifications }} notifications</span>\n    </div>\n  </div>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    title: string;\n    subtitle: string;\n    sectionLabel: string;\n    notifications: number;\n    collapsed: boolean;\n  }\n\n  export let props: Props;\n\n  function handleToggleSidebar() {\n    emit(\"toggle-sidebar\", null);\n  }\n\n  function handleQueueRefresh() {\n    emit(\"queue-refresh\", null);\n  }\n\n  function handleOpenNotifications() {\n    emit(\"open-notifications\", null);\n  }\n\n  function handleClearNotifications() {\n    emit(\"clear-notifications\", null);\n  }\n</script>\n\n<style>\n  .workspace-header {\n    display: flex;\n    align-items: start;\n    justify-content: space-between;\n    gap: 1rem;\n    padding: 1.25rem 1.5rem;\n    border: 1px solid #d7e0e8;\n    border-radius: 24px;\n    background: rgba(255, 255, 255, 0.86);\n    backdrop-filter: blur(12px);\n    box-shadow: 0 16px 42px rgba(24, 44, 66, 0.1);\n  }\n\n  .workspace-header__eyebrow,\n  .workspace-header__subtitle,\n  .workspace-header__section,\n  .workspace-header__notification {\n    color: #607086;\n  }\n\n  .workspace-header__section {\n    font-weight: 600;\n  }\n\n  .workspace-header__actions {\n    display: flex;\n    flex-wrap: wrap;\n    align-items: center;\n    justify-content: end;\n    gap: 0.75rem;\n  }\n\n  .workspace-header__ghost,\n  .workspace-header__primary {\n    border-radius: 999px;\n    padding: 0.75rem 1rem;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .workspace-header__ghost {\n    border: 1px solid #cad4df;\n    background: #fff;\n    color: #30455d;\n  }\n\n  .workspace-header__ghost:hover {\n    border-color: #aebbc9;\n    background: #f7fafc;\n  }\n\n  .workspace-header__primary {\n    border: none;\n    background: #182c42;\n    color: #fff;\n  }\n\n  .workspace-header__primary:hover {\n    background: #0f2136;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 963, 963, 974]);
    expect_section(doc.script, [977, 983, 984, 993, 976, 994, 994, 1484, 1484, 1493]);
    if doc.style is style {
        expect_section(style, [1496, 1501, 1501, 1501, 1495, 1502, 1502, 2709, 2709, 2717]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/WorkspaceShell.weiv" {
    const doc = parse("<template>\n  <main :class=\"shellClass()\">\n    <header class=\"workspace-shell__header\">\n      <slot name=\"header\"></slot>\n    </header>\n\n    <section class=\"workspace-shell__toolbar\">\n      <slot name=\"toolbar\"></slot>\n    </section>\n\n    <div class=\"workspace-shell__body\">\n      <aside class=\"workspace-shell__sidebar\">\n        <slot name=\"sidebar\"></slot>\n      </aside>\n\n      <section class=\"workspace-shell__main\">\n        <slot></slot>\n      </section>\n\n      <aside class=\"workspace-shell__detail\">\n        <slot name=\"detail\"></slot>\n      </aside>\n    </div>\n  </main>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    collapsed: boolean;\n  }\n\n  export let props: Props;\n\n  function shellClass() {\n    return props.collapsed ? \"workspace-shell workspace-shell--collapsed\" : \"workspace-shell\";\n  }\n</script>\n\n<style>\n  .workspace-shell {\n    min-height: 100vh;\n    padding: 1.25rem;\n    background:\n      radial-gradient(circle at 12% 2%, rgba(255, 214, 166, 0.65), transparent 30%),\n      radial-gradient(circle at 88% 4%, rgba(190, 220, 255, 0.55), transparent 33%),\n      linear-gradient(180deg, #f8fbff 0%, #edf3f8 100%);\n    color: #182c42;\n    font-family: \"IBM Plex Sans\", \"Helvetica Neue\", sans-serif;\n  }\n\n  .workspace-shell__body {\n    display: grid;\n    grid-template-columns: 260px minmax(0, 1fr) 320px;\n    gap: 1rem;\n    align-items: start;\n  }\n\n  .workspace-shell--collapsed .workspace-shell__body {\n    grid-template-columns: 120px minmax(0, 1fr) 320px;\n  }\n\n  .workspace-shell__header {\n    margin-bottom: 0.75rem;\n  }\n\n  .workspace-shell__toolbar {\n    margin-bottom: 1rem;\n  }\n\n  .workspace-shell__main,\n  .workspace-shell__detail {\n    min-width: 0;\n  }\n\n  @media (max-width: 1100px) {\n    .workspace-shell__body,\n    .workspace-shell--collapsed .workspace-shell__body {\n      grid-template-columns: 1fr;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 578, 578, 589]);
    expect_section(doc.script, [592, 598, 599, 608, 591, 609, 609, 819, 819, 828]);
    if doc.style is style {
        expect_section(style, [831, 836, 836, 836, 830, 837, 837, 1856, 1856, 1864]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/components/WorkspaceSidebar.weiv" {
    const doc = parse("<template>\n  <nav :class=\"sidebarClass()\">\n    <section class=\"workspace-sidebar__section\">\n      <p class=\"workspace-sidebar__label\">Workspaces</p>\n      <button\n        #for=\"workspace in workspaces()\"\n        :class=\"workspaceClass(workspace.id)\"\n        @click=\"selectWorkspace(workspace.id)\"\n      >\n        <span>{{ workspace.key }}</span>\n        <small>{{ workspace.name }}</small>\n      </button>\n    </section>\n\n    <section class=\"workspace-sidebar__section\">\n      <p class=\"workspace-sidebar__label\">Projects</p>\n      <button\n        #for=\"project in projects()\"\n        :class=\"projectClass(project.id)\"\n        @click=\"selectProject(project.id)\"\n      >\n        <span>{{ project.key }}</span>\n        <small>{{ project.name }}</small>\n      </button>\n    </section>\n\n    <section class=\"workspace-sidebar__section\">\n      <p class=\"workspace-sidebar__label\">Views</p>\n      <button :class=\"itemClass(overviewPath())\" @click=\"showOverview\">\n        <span>Overview</span>\n        <small>metrics, recent movement</small>\n      </button>\n      <button :class=\"itemClass(issuesPath())\" @click=\"showIssues\">\n        <span>Issues</span>\n        <small>list, filters, selection</small>\n      </button>\n      <button :class=\"itemClass(boardPath())\" @click=\"showBoard\">\n        <span>Board</span>\n        <small>status grouped work</small>\n      </button>\n      <button :class=\"itemClass(notificationsPath())\" @click=\"showNotifications\">\n        <span>Notifications</span>\n        <small>mentions and activity</small>\n      </button>\n      <button :class=\"itemClass(membersPath())\" @click=\"showMembers\">\n        <span>Members</span>\n        <small>roles and focus</small>\n      </button>\n      <button :class=\"itemClass(settingsPath())\" @click=\"showSettings\">\n        <span>Settings</span>\n        <small>preferences and rules</small>\n      </button>\n    </section>\n\n    <p class=\"workspace-sidebar__status\">{{ props.statusMessage }}</p>\n  </nav>\n</template>\n\n<script lang=\"ts\">\n  import {\n    boardRoute,\n    issuesRoute,\n    listProjects,\n    listWorkspaces,\n    membersRoute,\n    notificationsRoute,\n    settingsRoute,\n    workspaceRoute\n  } from \"../state/workspace.ts\";\n\n  export interface Props {\n    currentWorkspaceId: string;\n    selectedProjectId: string;\n    currentPath: string;\n    collapsed: boolean;\n    statusMessage: string;\n  }\n\n  export let props: Props;\n\n  function sidebarClass() {\n    return props.collapsed ? \"workspace-sidebar workspace-sidebar--collapsed\" : \"workspace-sidebar\";\n  }\n\n  function workspaces() {\n    return listWorkspaces();\n  }\n\n  function projects() {\n    return listProjects(props.currentWorkspaceId);\n  }\n\n  function overviewPath() {\n    return workspaceRoute(props.currentWorkspaceId);\n  }\n\n  function issuesPath() {\n    return issuesRoute(props.currentWorkspaceId);\n  }\n\n  function boardPath() {\n    return boardRoute(props.currentWorkspaceId);\n  }\n\n  function membersPath() {\n    return membersRoute(props.currentWorkspaceId);\n  }\n\n  function notificationsPath() {\n    return notificationsRoute(props.currentWorkspaceId);\n  }\n\n  function settingsPath() {\n    return settingsRoute(props.currentWorkspaceId);\n  }\n\n  function itemClass(path: string) {\n    return props.currentPath === path\n      ? \"workspace-sidebar__item workspace-sidebar__item--active\"\n      : \"workspace-sidebar__item\";\n  }\n\n  function workspaceClass(workspaceId: string) {\n    return props.currentWorkspaceId === workspaceId\n      ? \"workspace-sidebar__workspace workspace-sidebar__workspace--active\"\n      : \"workspace-sidebar__workspace\";\n  }\n\n  function projectClass(projectId: string) {\n    return props.selectedProjectId === projectId\n      ? \"workspace-sidebar__workspace workspace-sidebar__workspace--active\"\n      : \"workspace-sidebar__workspace\";\n  }\n\n  function showOverview() {\n    emit(\"navigate\", overviewPath());\n  }\n\n  function showIssues() {\n    emit(\"navigate\", issuesPath());\n  }\n\n  function showBoard() {\n    emit(\"navigate\", boardPath());\n  }\n\n  function showMembers() {\n    emit(\"navigate\", membersPath());\n  }\n\n  function showNotifications() {\n    emit(\"navigate\", notificationsPath());\n  }\n\n  function showSettings() {\n    emit(\"navigate\", settingsPath());\n  }\n\n  function selectWorkspace(workspaceId: string) {\n    emit(\"switch-workspace\", workspaceId);\n  }\n\n  function selectProject(projectId: string) {\n    emit(\"switch-project\", projectId);\n  }\n</script>\n\n<style>\n  .workspace-sidebar {\n    display: grid;\n    gap: 1rem;\n    padding: 1rem;\n    border: 1px solid #d7e0e8;\n    border-radius: 20px;\n    background: rgba(255, 255, 255, 0.92);\n  }\n\n  .workspace-sidebar__section {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .workspace-sidebar__label,\n  .workspace-sidebar__status {\n    color: #6d7b8d;\n  }\n\n  .workspace-sidebar__workspace,\n  .workspace-sidebar__item {\n    display: grid;\n    gap: 0.2rem;\n    width: 100%;\n    padding: 0.8rem 0.9rem;\n    border-radius: 16px;\n    background: #fff;\n    text-align: left;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .workspace-sidebar__workspace {\n    border: 1px solid #dde5ed;\n    color: #42556c;\n  }\n\n  .workspace-sidebar__workspace:hover {\n    border-color: #c8d6e5;\n    background: #fbfdff;\n  }\n\n  .workspace-sidebar__workspace--active {\n    border-color: #2f7f73;\n    box-shadow: inset 0 0 0 1px rgba(47, 127, 115, 0.16);\n    color: #173f46;\n  }\n\n  .workspace-sidebar__item {\n    border: 1px solid #dde5ed;\n    color: #182c42;\n  }\n\n  .workspace-sidebar__item:hover {\n    border-color: #c2d0df;\n    background: #f6faff;\n  }\n\n  .workspace-sidebar__item--active {\n    border-color: #182c42;\n    background: #182c42;\n    color: #fff;\n  }\n\n  .workspace-sidebar__item small,\n  .workspace-sidebar__workspace small {\n    opacity: 0.78;\n  }\n\n  .workspace-sidebar--collapsed {\n    padding: 0.75rem;\n  }\n\n  .workspace-sidebar--collapsed .workspace-sidebar__label,\n  .workspace-sidebar--collapsed .workspace-sidebar__status,\n  .workspace-sidebar--collapsed .workspace-sidebar__workspace small,\n  .workspace-sidebar--collapsed .workspace-sidebar__item small {\n    display: none;\n  }\n\n  .workspace-sidebar--collapsed .workspace-sidebar__workspace,\n  .workspace-sidebar--collapsed .workspace-sidebar__item {\n    min-height: 4.5rem;\n    justify-items: center;\n    align-content: center;\n    padding: 0.7rem 0.45rem;\n    text-align: center;\n  }\n\n  .workspace-sidebar--collapsed .workspace-sidebar__workspace span,\n  .workspace-sidebar--collapsed .workspace-sidebar__item span {\n    display: block;\n    max-width: 100%;\n    font-size: 0.82rem;\n    line-height: 1.15;\n    word-break: break-word;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1953, 1953, 1964]);
    expect_section(doc.script, [1967, 1973, 1974, 1983, 1966, 1984, 1984, 4393, 4393, 4402]);
    if doc.style is style {
        expect_section(style, [4405, 4410, 4410, 4410, 4404, 4411, 4411, 6581, 6581, 6589]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/IssueBoardPage.weiv" {
    const doc = parse("<template>\n  <section class=\"issue-board\">\n    <Panel #for=\"column in columns()\">\n      <template slot:header>\n        <div>\n          <h2>{{ column.label }}</h2>\n          <p class=\"issue-board__subhead\">{{ column.items.length }} issues</p>\n        </div>\n      </template>\n\n      <EmptyState #if=\"column.items.length === 0\">\n        <template slot:message>\n          <p>{{ column.label }} is clear.</p>\n        </template>\n        <p>Work will appear here as issue status changes.</p>\n      </EmptyState>\n\n      <div #else class=\"issue-board__cards\">\n        <article\n          #for=\"issue in column.items\"\n          class=\"issue-board__card\"\n        >\n          <strong>{{ issue.title }}</strong>\n          <p>{{ issue.summary }}</p>\n          <small>{{ issue.owner }} · {{ issue.priority }}</small>\n          <div class=\"issue-board__top-actions\">\n            <button class=\"issue-board__open\" @click=\"openIssue(issue.id)\" type=\"button\">Open detail</button>\n            <button class=\"issue-board__advance\" @click=\"advanceIssue(issue.id)\" type=\"button\">Advance</button>\n          </div>\n          <span class=\"issue-board__move-label\">Move to</span>\n          <div class=\"issue-board__move-row\">\n            <button\n              class=\"issue-board__move\"\n              :disabled=\"issue.status === 'backlog'\"\n              @click=\"moveToBacklog(issue.id)\"\n              type=\"button\"\n            >\n              Backlog\n            </button>\n            <button\n              class=\"issue-board__move\"\n              :disabled=\"issue.status === 'in-progress'\"\n              @click=\"moveToInProgress(issue.id)\"\n              type=\"button\"\n            >\n              In progress\n            </button>\n            <button\n              class=\"issue-board__move\"\n              :disabled=\"issue.status === 'review'\"\n              @click=\"moveToReview(issue.id)\"\n              type=\"button\"\n            >\n              Review\n            </button>\n            <button\n              class=\"issue-board__move\"\n              :disabled=\"issue.status === 'done'\"\n              @click=\"moveToDone(issue.id)\"\n              type=\"button\"\n            >\n              Done\n            </button>\n          </div>\n        </article>\n      </div>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import EmptyState from \"../components/EmptyState.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import { cycleIssueStatus, issueRoute, listIssues, moveIssueToStatus, navigateTo, workspaceShared } from \"../state/workspace.ts\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n\n  function boardItems(status: string) {\n    workspaceShared.saveTick;\n    return listIssues(props.workspaceId, workspaceShared.selectedProjectId)\n      .filter((issue) => issue.status === status);\n  }\n\n  function columns() {\n    return [\n      { id: \"backlog\", label: \"Backlog\", items: boardItems(\"backlog\") },\n      { id: \"in-progress\", label: \"In progress\", items: boardItems(\"in-progress\") },\n      { id: \"review\", label: \"Review\", items: boardItems(\"review\") },\n      { id: \"done\", label: \"Done\", items: boardItems(\"done\") }\n    ];\n  }\n\n  function openIssue(issueId: string) {\n    navigateTo(issueRoute(props.workspaceId, issueId));\n  }\n\n  function advanceIssue(issueId: string) {\n    cycleIssueStatus(issueId);\n  }\n\n  function moveIssue(issueId: string, status: \"backlog\" | \"in-progress\" | \"review\" | \"done\") {\n    moveIssueToStatus(issueId, status);\n  }\n\n  function moveToBacklog(issueId: string) {\n    moveIssue(issueId, \"backlog\");\n  }\n\n  function moveToInProgress(issueId: string) {\n    moveIssue(issueId, \"in-progress\");\n  }\n\n  function moveToReview(issueId: string) {\n    moveIssue(issueId, \"review\");\n  }\n\n  function moveToDone(issueId: string) {\n    moveIssue(issueId, \"done\");\n  }\n</script>\n\n<style>\n  .issue-board {\n    display: grid;\n    grid-template-columns: repeat(2, minmax(0, 1fr));\n    gap: 0.9rem;\n  }\n\n  .issue-board__subhead {\n    color: #68798e;\n    font-size: 0.88rem;\n  }\n\n  .issue-board__cards {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .issue-board__card {\n    display: grid;\n    gap: 0.35rem;\n    padding: 0.85rem;\n    border: 1px solid #dde5ed;\n    border-radius: 16px;\n    background: linear-gradient(180deg, #f9fbff 0%, #f4f8fc 100%);\n    text-align: left;\n    font: inherit;\n    color: #182c42;\n    box-shadow: 0 8px 18px rgba(24, 44, 66, 0.06);\n  }\n\n  .issue-board__card strong {\n    line-height: 1.25;\n  }\n\n  .issue-board__card p {\n    color: #41556d;\n    line-height: 1.35;\n  }\n\n  .issue-board__card small {\n    color: #6a7d93;\n  }\n\n  .issue-board__open {\n    border: 1px solid #dbe4ec;\n    border-radius: 999px;\n    background: #fff;\n    color: #30455d;\n    font: inherit;\n    font-size: 0.82rem;\n    padding: 0.35rem 0.65rem;\n    cursor: pointer;\n  }\n\n  .issue-board__top-actions {\n    display: flex;\n    gap: 0.4rem;\n    margin-top: 0.1rem;\n  }\n\n  .issue-board__advance {\n    border: none;\n    border-radius: 999px;\n    background: #182c42;\n    color: #fff;\n    font: inherit;\n    font-size: 0.82rem;\n    padding: 0.35rem 0.65rem;\n    cursor: pointer;\n  }\n\n  .issue-board__open:hover,\n  .issue-board__move:hover {\n    border-color: #c0cfdf;\n    background: #fbfdff;\n  }\n\n  .issue-board__advance:hover {\n    background: #0f2136;\n  }\n\n  .issue-board__move-label {\n    margin-top: 0.1rem;\n    color: #647389;\n    font-size: 0.82rem;\n  }\n\n  .issue-board__move-row {\n    display: grid;\n    grid-template-columns: repeat(2, minmax(0, 1fr));\n    gap: 0.3rem;\n  }\n\n  .issue-board__move {\n    border: 1px solid #dbe4ec;\n    border-radius: 999px;\n    background: #fff;\n    color: #182c42;\n    font: inherit;\n    font-size: 0.8rem;\n    padding: 0.26rem 0.48rem;\n    cursor: pointer;\n  }\n\n  .issue-board__move:disabled {\n    cursor: default;\n    opacity: 0.45;\n  }\n\n  @media (max-width: 900px) {\n    .issue-board {\n      grid-template-columns: 1fr;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 2259, 2259, 2270]);
    expect_section(doc.script, [2273, 2279, 2280, 2289, 2272, 2290, 2290, 3810, 3810, 3819]);
    if doc.style is style {
        expect_section(style, [3822, 3827, 3827, 3827, 3821, 3828, 3828, 5906, 5906, 5914]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/IssueDetailPage.weiv" {
    const doc = parse("<template>\n  <section class=\"issue-detail-page\">\n    <Panel>\n      <template slot:header>\n        <div>\n          <h2>{{ issueTitle() }}</h2>\n          <p class=\"issue-detail-page__subhead\">Issue detail route with async save and shared state updates.</p>\n        </div>\n      </template>\n\n      <template slot:actions>\n        <button class=\"issue-detail-page__ghost\" @click=\"backToIssues\">Back to issues</button>\n      </template>\n\n      <EmptyState #if=\"!issue()\">\n        <template slot:message>\n          <p>The requested issue was not found.</p>\n        </template>\n        <p>Return to the issue list and select another item.</p>\n      </EmptyState>\n\n      <section #else class=\"issue-detail-page__content\">\n        <DetailSection :body=\"issue().summary\" :title=\"'Summary'\" />\n        <DetailSection :body=\"issue().detail\" :title=\"'Implementation notes'\" />\n\n        <div class=\"issue-detail-page__composer\">\n          <label>Add comment</label>\n          <div class=\"issue-detail-page__composer-row\">\n            <input\n              id=\"detail-note\"\n              :value=\"noteDraft\"\n              class=\"issue-detail-page__input\"\n              @change=\"handleDraftInput\"\n              @input=\"handleDraftInput\"\n              placeholder=\"Write a comment for your team\"\n              type=\"text\"\n            />\n            <button class=\"issue-detail-page__composer-submit\" @click=\"submitComment\" type=\"button\">Post</button>\n          </div>\n        </div>\n      </section>\n\n      <template slot:footer>\n        <div #if=\"issue()\" class=\"issue-detail-page__footer\">\n          <small>{{ saving ? \"Saving issue update...\" : statusLine() }}</small>\n          <button class=\"issue-detail-page__primary\" @click=\"saveIssue\">Advance status and save</button>\n        </div>\n      </template>\n    </Panel>\n\n    <div class=\"issue-detail-page__secondary\">\n      <Panel>\n        <template slot:header>\n          <div>\n            <h2>Metadata</h2>\n            <p class=\"issue-detail-page__subhead\">Shared route-aware selection</p>\n          </div>\n        </template>\n\n        <ul #if=\"issue()\" class=\"issue-detail-page__meta\">\n          <li>Status: {{ issue().status }}</li>\n          <li>Priority: {{ issue().priority }}</li>\n          <li>Owner: {{ issue().owner }}</li>\n          <li>Watchers: {{ issue().watchers }}</li>\n        </ul>\n      </Panel>\n\n      <Panel>\n        <template slot:header>\n          <div>\n            <h2>Recent activity</h2>\n            <p class=\"issue-detail-page__subhead\">Simple mocked activity stream</p>\n          </div>\n        </template>\n\n        <ul #if=\"issue()\" class=\"issue-detail-page__activity\">\n          <li>{{ issue().owner }} updated this issue {{ issue().updatedMinutesAgo }} minutes ago.</li>\n          <li>Route-level save flow is wired through `setTimeout` and shared observable updates.</li>\n          <li #for=\"comment in issueComments()\">{{ comment.author }} · {{ comment.minutesAgo }}m · {{ comment.body }}</li>\n          <li #if=\"noteDraft\">Draft: {{ noteDraft }}</li>\n        </ul>\n      </Panel>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import DetailSection from \"../components/DetailSection.weiv\";\n  import EmptyState from \"../components/EmptyState.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import {\n    addComment,\n    bumpNotifications,\n    cycleIssueStatus,\n    findIssue,\n    issuesRoute,\n    listComments,\n    navigateTo,\n    workspaceShared\n  } from \"../state/workspace.ts\";\n\n  export interface Props {\n    workspaceId: string;\n    issueId: string;\n  }\n\n  export let props: Props;\n  let saving = false;\n  let noteDraft = \"\";\n\n  function issue() {\n    workspaceShared.saveTick;\n    return findIssue(props.issueId);\n  }\n\n  function issueTitle() {\n    const current = issue();\n    return current ? current.title : \"Issue detail\";\n  }\n\n  function statusLine() {\n    const current = issue();\n    if (!current) {\n      return \"No issue selected.\";\n    }\n    return `${current.status} · ${current.watchers} watchers`;\n  }\n\n  function backToIssues() {\n    navigateTo(issuesRoute(props.workspaceId));\n  }\n\n  function issueComments() {\n    workspaceShared.saveTick;\n    return listComments(props.issueId);\n  }\n\n  function submitComment() {\n    const input = typeof document !== \"undefined\"\n      ? (document.getElementById(\"detail-note\") as HTMLInputElement | null)\n      : null;\n    const body = String(input?.value ?? noteDraft).trim();\n    if (!body) return;\n    addComment(props.issueId, \"You\", body);\n    noteDraft = \"\";\n    if (input) {\n      input.value = \"\";\n    }\n  }\n\n  function handleDraftInput(event: any) {\n    noteDraft = String(event?.target?.value ?? \"\");\n  }\n\n  function saveIssue() {\n    if (!issue()) {\n      return;\n    }\n    saving = true;\n    setTimeout(() => {\n      cycleIssueStatus(props.issueId);\n      bumpNotifications();\n      saving = false;\n    }, 0);\n  }\n</script>\n\n<style>\n  .issue-detail-page {\n    display: grid;\n    gap: 1rem;\n  }\n\n  .issue-detail-page__secondary {\n    display: grid;\n    gap: 1rem;\n    grid-template-columns: repeat(2, minmax(0, 1fr));\n  }\n\n  .issue-detail-page__subhead {\n    color: #68798e;\n    line-height: 1.35;\n  }\n\n  .issue-detail-page__content,\n  .issue-detail-page__meta,\n  .issue-detail-page__activity {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .issue-detail-page__content {\n    gap: 0.85rem;\n  }\n\n  .issue-detail-page__meta,\n  .issue-detail-page__activity {\n    list-style: none;\n    margin: 0;\n    padding: 0;\n  }\n\n  .issue-detail-page__composer {\n    display: grid;\n    gap: 0.45rem;\n    padding-top: 0.85rem;\n    border-top: 1px solid #edf2f6;\n    margin-top: 0.2rem;\n  }\n\n  .issue-detail-page__composer-row {\n    display: grid;\n    grid-template-columns: minmax(0, 1fr) auto;\n    gap: 0.5rem;\n    align-items: center;\n  }\n\n  .issue-detail-page__input {\n    border: 1px solid #cad4df;\n    border-radius: 12px;\n    padding: 0.75rem 0.85rem;\n    font: inherit;\n    background: #fcfeff;\n  }\n\n  .issue-detail-page__input:focus {\n    outline: none;\n    border-color: #9bb0c8;\n    box-shadow: 0 0 0 3px rgba(71, 122, 176, 0.14);\n  }\n\n  .issue-detail-page__composer-submit {\n    border: none;\n    border-radius: 10px;\n    padding: 0.62rem 0.78rem;\n    background: #17344f;\n    color: #fff;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .issue-detail-page__composer-submit:hover {\n    background: #122a3f;\n  }\n\n  .issue-detail-page__ghost,\n  .issue-detail-page__primary {\n    border-radius: 999px;\n    padding: 0.55rem 0.85rem;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .issue-detail-page__ghost {\n    border: 1px solid #dbe4ec;\n    background: #fff;\n  }\n\n  .issue-detail-page__ghost:hover {\n    border-color: #c4d2e0;\n    background: #f8fbff;\n  }\n\n  .issue-detail-page__primary {\n    border: none;\n    background: #182c42;\n    color: #fff;\n  }\n\n  .issue-detail-page__primary:hover {\n    background: #0f2136;\n  }\n\n  .issue-detail-page__footer {\n    display: flex;\n    align-items: center;\n    justify-content: space-between;\n    gap: 1rem;\n    padding-top: 0.2rem;\n  }\n\n  .issue-detail-page__meta li,\n  .issue-detail-page__activity li {\n    padding: 0.4rem 0.55rem;\n    border: 1px solid #e7edf4;\n    border-radius: 12px;\n    background: #fbfdff;\n    color: #2b445f;\n  }\n\n  @media (max-width: 900px) {\n    .issue-detail-page__secondary {\n      grid-template-columns: 1fr;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 3075, 3075, 3086]);
    expect_section(doc.script, [3089, 3095, 3096, 3105, 3088, 3106, 3106, 4872, 4872, 4881]);
    if doc.style is style {
        expect_section(style, [4884, 4889, 4889, 4889, 4883, 4890, 4890, 7335, 7335, 7343]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/IssueListPage.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <template slot:header>\n      <div>\n        <h2>Issue list</h2>\n        <p class=\"activity-feed__subhead\">{{ projectLabel() }} · {{ visibleIssues().length }} visible issues</p>\n      </div>\n    </template>\n\n    <template slot:actions>\n      <button :class=\"filterClass('all')\" @click=\"showAll\">All</button>\n      <button :class=\"filterClass('active')\" @click=\"showActive\">Active</button>\n      <button :class=\"filterClass('review')\" @click=\"showReview\">Review</button>\n    </template>\n\n    <EmptyState #if=\"visibleIssues().length === 0\">\n      <template slot:message>\n        <p>No issues match the current filter.</p>\n      </template>\n      <p>Switch filters or move work back into the active queue.</p>\n    </EmptyState>\n\n    <ul #else class=\"activity-feed__list\">\n      <ActivityItem\n        #for=\"issue in visibleIssues()\"\n        :id=\"issue.id\"\n        :owner=\"issue.owner\"\n        :priority=\"issue.priority\"\n        :selected=\"workspaceShared.selectedIssueId === issue.id\"\n        :status=\"issue.status\"\n        :summary=\"issue.summary\"\n        :title=\"issue.title\"\n        @open-issue=\"openIssue\"\n      />\n    </ul>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import ActivityItem from \"../components/ActivityItem.weiv\";\n  import EmptyState from \"../components/EmptyState.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import { findProject, issueRoute, listIssues, navigateTo, workspaceShared } from \"../state/workspace.ts\";\n\n  export type IssueFilter = \"all\" | \"active\" | \"review\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n  let filter: IssueFilter = \"all\";\n\n  function allIssues() {\n    workspaceShared.saveTick;\n    return listIssues(props.workspaceId, workspaceShared.selectedProjectId);\n  }\n\n  function projectLabel() {\n    const project = findProject(workspaceShared.selectedProjectId);\n    return project ? `${project.key} · ${project.name}` : props.workspaceId;\n  }\n\n  function visibleIssues() {\n    if (filter === \"active\") {\n      return allIssues().filter((issue) => issue.status !== \"done\");\n    }\n    if (filter === \"review\") {\n      return allIssues().filter((issue) => issue.status === \"review\");\n    }\n    return allIssues();\n  }\n\n  function filterClass(nextFilter: IssueFilter) {\n    return filter === nextFilter ? \"activity-feed__filter activity-feed__filter--active\" : \"activity-feed__filter\";\n  }\n\n  function showAll() {\n    filter = \"all\";\n  }\n\n  function showActive() {\n    filter = \"active\";\n  }\n\n  function showReview() {\n    filter = \"review\";\n  }\n\n  function openIssue(issueId: string) {\n    navigateTo(issueRoute(props.workspaceId, issueId));\n  }\n</script>\n\n<style>\n  .activity-feed__subhead {\n    color: #68798e;\n  }\n\n  .activity-feed__filter {\n    margin-left: 0.4rem;\n    border: 1px solid #dbe4ec;\n    border-radius: 999px;\n    padding: 0.5rem 0.75rem;\n    background: #fff;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .activity-feed__filter--active {\n    border-color: #182c42;\n    background: #182c42;\n    color: #fff;\n  }\n\n  .activity-feed__list {\n    list-style: none;\n    padding: 0;\n    margin: 0;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1160, 1160, 1171]);
    expect_section(doc.script, [1174, 1180, 1181, 1190, 1173, 1191, 1191, 2662, 2662, 2671]);
    if doc.style is style {
        expect_section(style, [2674, 2679, 2679, 2679, 2673, 2680, 2680, 3130, 3130, 3138]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/MembersPage.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <template slot:header>\n      <div>\n        <h2>Members</h2>\n        <p class=\"members-page__subhead\">Team context for the current workspace.</p>\n      </div>\n    </template>\n\n    <EmptyState #if=\"workspaceMembers().length === 0\">\n      <template slot:message>\n        <p>No members are assigned to this workspace.</p>\n      </template>\n      <p>Invite teammates once the workspace is ready.</p>\n    </EmptyState>\n\n    <ul #else class=\"members-page__list\">\n      <li #for=\"member in workspaceMembers()\" class=\"members-page__row\">\n        <strong>{{ member.name }}</strong>\n        <span>{{ member.role }}</span>\n        <small>{{ member.focus }}</small>\n      </li>\n    </ul>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import EmptyState from \"../components/EmptyState.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import { listMembers } from \"../state/workspace.ts\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n\n  function workspaceMembers() {\n    return listMembers(props.workspaceId);\n  }\n</script>\n\n<style>\n  .members-page__subhead {\n    color: #68798e;\n  }\n\n  .members-page__list {\n    list-style: none;\n    margin: 0;\n    padding: 0;\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .members-page__row {\n    display: grid;\n    gap: 0.25rem;\n    padding-top: 0.75rem;\n    border-top: 1px solid #edf2f6;\n  }\n\n  .members-page__row:first-child {\n    padding-top: 0;\n    border-top: none;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 711, 711, 722]);
    expect_section(doc.script, [725, 731, 732, 741, 724, 742, 742, 1069, 1069, 1078]);
    if doc.style is style {
        expect_section(style, [1081, 1086, 1086, 1086, 1080, 1087, 1087, 1466, 1466, 1474]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/NotificationsPage.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <template slot:header>\n      <div>\n        <h2>Notifications</h2>\n        <p class=\"notifications-page__subhead\">{{ unreadCount() }} unread · {{ items().length }} total</p>\n      </div>\n    </template>\n\n    <EmptyState #if=\"items().length === 0\">\n      <template slot:message>\n        <p>No notifications for this workspace.</p>\n      </template>\n      <p>Team mentions and issue updates will appear here.</p>\n    </EmptyState>\n\n    <ul #else class=\"notifications-page__list\">\n      <li #for=\"item in items()\" :class=\"rowClass(item.read)\">\n        <div class=\"notifications-page__body\">\n          <strong>{{ item.title }}</strong>\n          <p>{{ item.detail }}</p>\n          <small>{{ item.minutesAgo }}m ago</small>\n        </div>\n        <div class=\"notifications-page__actions\">\n          <button class=\"notifications-page__ghost\" :disabled=\"!item.issueId\" @click=\"openIssue(item.issueId)\">Open issue</button>\n          <button class=\"notifications-page__primary\" :disabled=\"item.read\" @click=\"markRead(item.id)\">\n            {{ item.read ? \"Read\" : \"Mark read\" }}\n          </button>\n        </div>\n      </li>\n    </ul>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import EmptyState from \"../components/EmptyState.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import { issueRoute, listNotifications, markNotificationRead, navigateTo } from \"../state/workspace.ts\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n\n  function items() {\n    return listNotifications(props.workspaceId);\n  }\n\n  function unreadCount() {\n    return items().filter((item) => !item.read).length;\n  }\n\n  function rowClass(read: boolean) {\n    return read ? \"notifications-page__row notifications-page__row--read\" : \"notifications-page__row\";\n  }\n\n  function markRead(notificationId: string) {\n    markNotificationRead(notificationId);\n  }\n\n  function openIssue(issueId: string | null) {\n    if (!issueId) return;\n    navigateTo(issueRoute(props.workspaceId, issueId));\n  }\n</script>\n\n<style>\n  .notifications-page__subhead {\n    color: #68798e;\n  }\n\n  .notifications-page__list {\n    list-style: none;\n    margin: 0;\n    padding: 0;\n    display: grid;\n    gap: 0.6rem;\n  }\n\n  .notifications-page__row {\n    display: grid;\n    gap: 0.5rem;\n    grid-template-columns: minmax(0, 1fr) auto;\n    align-items: center;\n    border: 1px solid #d8e2ec;\n    border-radius: 14px;\n    padding: 0.7rem 0.8rem;\n    background: #f8fbff;\n  }\n\n  .notifications-page__row--read {\n    opacity: 0.72;\n    background: #fcfdff;\n  }\n\n  .notifications-page__body {\n    display: grid;\n    gap: 0.25rem;\n  }\n\n  .notifications-page__body p,\n  .notifications-page__body small {\n    margin: 0;\n    color: #5e7188;\n  }\n\n  .notifications-page__actions {\n    display: flex;\n    gap: 0.45rem;\n  }\n\n  .notifications-page__ghost,\n  .notifications-page__primary {\n    border-radius: 999px;\n    padding: 0.4rem 0.68rem;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .notifications-page__ghost {\n    border: 1px solid #d0dae4;\n    background: #fff;\n    color: #2e465f;\n  }\n\n  .notifications-page__primary {\n    border: none;\n    background: #16354f;\n    color: #fff;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1163, 1163, 1174]);
    expect_section(doc.script, [1177, 1183, 1184, 1193, 1176, 1194, 1194, 2028, 2028, 2037]);
    if doc.style is style {
        expect_section(style, [2040, 2045, 2045, 2045, 2039, 2046, 2046, 3188, 3188, 3196]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/OverviewPage.weiv" {
    const doc = parse("<template>\n  <section class=\"dashboard-section\">\n    <Panel>\n      <template slot:header>\n        <div>\n          <h2>{{ workspaceName() }} overview</h2>\n          <p class=\"dashboard-section__subhead\">Health, issue flow, and recent movement.</p>\n        </div>\n      </template>\n\n      <template slot:actions>\n        <button class=\"dashboard-section__action\" @click=\"openIssues\">Open issues</button>\n        <button class=\"dashboard-section__action\" @click=\"openBoard\">View board</button>\n      </template>\n\n      <MetricGrid :metrics=\"workspaceMetrics()\" />\n    </Panel>\n\n    <Panel>\n      <template slot:header>\n        <div>\n          <h2>Recent issue movement</h2>\n          <p class=\"dashboard-section__subhead\">{{ recentSummary() }}</p>\n        </div>\n      </template>\n\n      <ul class=\"dashboard-section__facts\">\n        <li #for=\"issue in recentIssues()\">\n          <strong>{{ issue.title }}</strong>\n          <span>{{ issue.status }} · {{ issue.watchers }} watchers</span>\n        </li>\n      </ul>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import MetricGrid from \"../components/MetricGrid.weiv\";\n  import Panel from \"../components/Panel.weiv\";\n  import {\n    boardRoute,\n    findProject,\n    findWorkspace,\n    issuesRoute,\n    listIssues,\n    listMetrics,\n    navigateTo,\n    workspaceShared\n  } from \"../state/workspace.ts\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n\n  function workspaceName() {\n    const workspace = findWorkspace(props.workspaceId);\n    return workspace ? workspace.name : \"Workspace\";\n  }\n\n  function workspaceMetrics() {\n    return listMetrics(props.workspaceId);\n  }\n\n  function selectedProjectName() {\n    const project = findProject(workspaceShared.selectedProjectId);\n    return project ? project.name : \"All projects\";\n  }\n\n  function recentIssues() {\n    workspaceShared.saveTick;\n    return listIssues(props.workspaceId, workspaceShared.selectedProjectId).slice(0, 3);\n  }\n\n  function recentSummary() {\n    return `${recentIssues().length} issues visible in ${selectedProjectName()}.`;\n  }\n\n  function openIssues() {\n    navigateTo(issuesRoute(props.workspaceId));\n  }\n\n  function openBoard() {\n    navigateTo(boardRoute(props.workspaceId));\n  }\n</script>\n\n<style>\n  .dashboard-section {\n    display: grid;\n    gap: 1rem;\n  }\n\n  .dashboard-section__subhead {\n    color: #647389;\n  }\n\n  .dashboard-section__action {\n    margin-left: 0.5rem;\n    border: 1px solid #dbe4ec;\n    border-radius: 999px;\n    padding: 0.55rem 0.85rem;\n    background: #fff;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .dashboard-section__facts {\n    display: grid;\n    gap: 0.75rem;\n    list-style: none;\n    margin: 0;\n    padding: 0;\n    color: #42556c;\n  }\n\n  .dashboard-section__facts li {\n    display: flex;\n    justify-content: space-between;\n    gap: 1rem;\n    padding-top: 0.75rem;\n    border-top: 1px solid #edf2f6;\n  }\n\n  .dashboard-section__facts li:first-child {\n    padding-top: 0;\n    border-top: none;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 1039, 1039, 1050]);
    expect_section(doc.script, [1053, 1059, 1060, 1069, 1052, 1070, 1070, 2253, 2253, 2262]);
    if doc.style is style {
        expect_section(style, [2265, 2270, 2270, 2270, 2264, 2271, 2271, 3006, 3006, 3014]);
    } else {
        assert(false);
    }
}
test "test/examples/kanib/views/SettingsPage.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <template slot:header>\n      <div>\n        <h2>Settings</h2>\n        <p class=\"settings-page__subhead\">Small local-state form behavior inside a routed page.</p>\n      </div>\n    </template>\n\n    <div class=\"settings-page__group\">\n      <button :class=\"toggleClass(autopinEnabled)\" @click=\"toggleAutopin\">\n        {{ autopinEnabled ? \"Autopin enabled\" : \"Autopin disabled\" }}\n      </button>\n      <button :class=\"toggleClass(compactCards)\" @click=\"toggleCompactCards\">\n        {{ compactCards ? \"Compact board cards\" : \"Comfortable board cards\" }}\n      </button>\n    </div>\n\n    <template slot:footer>\n      <div class=\"settings-page__footer\">\n        <small>{{ savedMessage() }}</small>\n        <button class=\"settings-page__primary\" @click=\"saveSettings\">Save workspace settings</button>\n      </div>\n    </template>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import Panel from \"../components/Panel.weiv\";\n\n  export interface Props {\n    workspaceId: string;\n  }\n\n  export let props: Props;\n  let autopinEnabled = true;\n  let compactCards = false;\n  let saveCount = 0;\n\n  function toggleClass(active: boolean) {\n    return active ? \"settings-page__toggle settings-page__toggle--active\" : \"settings-page__toggle\";\n  }\n\n  function toggleAutopin() {\n    autopinEnabled = !autopinEnabled;\n  }\n\n  function toggleCompactCards() {\n    compactCards = !compactCards;\n  }\n\n  function saveSettings() {\n    saveCount += 1;\n  }\n\n  function savedMessage() {\n    return saveCount === 0\n      ? `Editing settings for ${props.workspaceId}.`\n      : `Saved ${saveCount} time${saveCount === 1 ? \"\" : \"s\"}.`;\n  }\n</script>\n\n<style>\n  .settings-page__subhead {\n    color: #68798e;\n  }\n\n  .settings-page__group {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .settings-page__toggle,\n  .settings-page__primary {\n    border-radius: 16px;\n    padding: 0.85rem 1rem;\n    font: inherit;\n    cursor: pointer;\n  }\n\n  .settings-page__toggle {\n    border: 1px solid #dde5ed;\n    background: #fff;\n    text-align: left;\n  }\n\n  .settings-page__toggle--active {\n    border-color: #2f7f73;\n    background: #edf8f5;\n  }\n\n  .settings-page__primary {\n    border: none;\n    background: #182c42;\n    color: #fff;\n  }\n\n  .settings-page__footer {\n    display: flex;\n    align-items: center;\n    justify-content: space-between;\n    gap: 1rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 856, 856, 867]);
    expect_section(doc.script, [870, 876, 877, 886, 869, 887, 887, 1623, 1623, 1632]);
    if doc.style is style {
        expect_section(style, [1635, 1640, 1640, 1640, 1634, 1641, 1641, 2332, 2332, 2340]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/Card.weiv" {
    const doc = parse("<template>\n  <section class=\"card\">\n    <header class=\"card__header\">\n      <slot name=\"header\">\n        <h2 class=\"card__fallback-title\">Untitled</h2>\n      </slot>\n    </header>\n    <div class=\"card__body\">\n      <slot>\n        <p class=\"card__fallback-body\">No body content.</p>\n      </slot>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .card {\n    border: 1px solid #ddd;\n    padding: 1rem;\n  }\n\n  .card__header {\n    margin-bottom: 0.75rem;\n  }\n\n  .card__fallback-title,\n  .card__fallback-body {\n    color: #666;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 320, 320, 331]);
    expect_section(doc.script, [334, 340, 341, 350, 333, 351, 351, 408, 408, 417]);
    if doc.style is style {
        expect_section(style, [420, 425, 425, 425, 419, 426, 426, 611, 611, 619]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/CardToggleUsage.weiv" {
    const doc = parse("<template>\n  <section class=\"card-toggle-usage\">\n    <button @click=\"toggleContent\">Toggle card content</button>\n\n    <Card>\n      <template slot:header>\n        <h2 class=\"card-toggle-usage__title\">{{ title }}</h2>\n        <p class=\"card-toggle-usage__eyebrow\">{{ eyebrow }}</p>\n      </template>\n\n      <p class=\"card-toggle-usage__body\">{{ body }}</p>\n    </Card>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import Card from \"./Card.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let title = \"Dashboard\";\n  let eyebrow = \"Daily overview\";\n  let body = \"Projected card body\";\n\n  function toggleContent() {\n    if (title === \"Dashboard\") {\n      title = \"Reports\";\n      eyebrow = \"Weekly summary\";\n      body = \"Projected report body\";\n    } else {\n      title = \"Dashboard\";\n      eyebrow = \"Daily overview\";\n      body = \"Projected card body\";\n    }\n  }\n</script>\n\n<style>\n  .card-toggle-usage {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .card-toggle-usage__title {\n    font-weight: 700;\n  }\n\n  .card-toggle-usage__eyebrow {\n    color: #666;\n  }\n\n  .card-toggle-usage__body {\n    line-height: 1.5;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 380, 380, 391]);
    expect_section(doc.script, [394, 400, 401, 410, 393, 411, 411, 881, 881, 890]);
    if doc.style is style {
        expect_section(style, [893, 898, 898, 898, 892, 899, 899, 1131, 1131, 1139]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/CardUsage.weiv" {
    const doc = parse("<template>\n  <Card>\n    <template slot:header>\n      <h2 class=\"card-usage__title\">{{ props.title }}</h2>\n      <p class=\"card-usage__eyebrow\">{{ props.eyebrow }}</p>\n    </template>\n\n    <p class=\"card-usage__body\">{{ props.body }}</p>\n  </Card>\n</template>\n\n<script lang=\"ts\">\n  import Card from \"./Card.weiv\";\n\n  export interface Props {\n    title: string;\n    eyebrow: string;\n    body: string;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .card-usage__title {\n    font-weight: 700;\n  }\n\n  .card-usage__eyebrow {\n    color: #666;\n  }\n\n  .card-usage__body {\n    line-height: 1.5;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 247, 247, 258]);
    expect_section(doc.script, [261, 267, 268, 277, 260, 278, 278, 431, 431, 440]);
    if doc.style is style {
        expect_section(style, [443, 448, 448, 448, 442, 449, 449, 595, 595, 603]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/EmptyState.weiv" {
    const doc = parse("<template>\n  <section class=\"empty-state\">\n    <header class=\"empty-state__header\">\n      <slot name=\"message\">\n        <p class=\"empty-state__fallback-message\">Nothing here yet.</p>\n      </slot>\n    </header>\n    <div class=\"empty-state__body\">\n      <slot>\n        <p class=\"empty-state__fallback-body\">No additional details.</p>\n      </slot>\n    </div>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .empty-state {\n    border: 1px dashed #aaa;\n    padding: 1rem;\n  }\n\n  .empty-state__fallback-message,\n  .empty-state__fallback-body {\n    color: #999;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 371, 371, 382]);
    expect_section(doc.script, [385, 391, 392, 401, 384, 402, 402, 459, 459, 468]);
    if doc.style is style {
        expect_section(style, [471, 476, 476, 476, 470, 477, 477, 635, 635, 643]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/EmptyStateFallbackUsage.weiv" {
    const doc = parse("<template>\n  <EmptyState />\n</template>\n\n<script lang=\"ts\">\n  import EmptyState from \"./EmptyState.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 28, 28, 39]);
    expect_section(doc.script, [42, 48, 49, 58, 41, 59, 59, 163, 163, 172]);
    if doc.style is style {
        expect_section(style, [175, 180, 180, 180, 174, 181, 181, 182, 182, 190]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/EmptyStateUsage.weiv" {
    const doc = parse("<template>\n  <EmptyState>\n    <h2 slot:message>{{ props.heading }}</h2>\n  </EmptyState>\n</template>\n\n<script lang=\"ts\">\n  import EmptyState from \"./EmptyState.weiv\";\n\n  export interface Props {\n    heading: string;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 88, 88, 99]);
    expect_section(doc.script, [102, 108, 109, 118, 101, 119, 119, 247, 247, 256]);
    if doc.style is style {
        expect_section(style, [259, 264, 264, 264, 258, 265, 265, 266, 266, 274]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/Panel.weiv" {
    const doc = parse("<template>\n  <section class=\"panel\">\n    <slot>\n      <p class=\"panel__fallback\">Fallback panel content</p>\n    </slot>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .panel {\n    padding: 1rem;\n  }\n\n  .panel__fallback {\n    color: #666;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 133, 133, 144]);
    expect_section(doc.script, [147, 153, 154, 163, 146, 164, 164, 221, 221, 230]);
    if doc.style is style {
        expect_section(style, [233, 238, 238, 238, 232, 239, 239, 317, 317, 325]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/PanelConditionalUsage.weiv" {
    const doc = parse("<template>\n  <section class=\"panel-conditional-usage\">\n    <button @click=\"toggleOpen\">Toggle details</button>\n\n    <Panel>\n      <p #if=\"open\" class=\"panel-conditional-usage__open\">Projected panel is open</p>\n      <p #else class=\"panel-conditional-usage__closed\">Projected panel is closed</p>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import Panel from \"./Panel.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let open = false;\n\n  function toggleOpen() {\n    open = !open;\n  }\n</script>\n\n<style>\n  .panel-conditional-usage {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .panel-conditional-usage__open {\n    font-weight: 600;\n  }\n\n  .panel-conditional-usage__closed {\n    color: #666;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 321, 321, 332]);
    expect_section(doc.script, [335, 341, 342, 351, 334, 352, 352, 516, 516, 525]);
    if doc.style is style {
        expect_section(style, [528, 533, 533, 533, 527, 534, 534, 726, 726, 734]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/PanelLoopUsage.weiv" {
    const doc = parse("<template>\n  <section class=\"panel-loop-usage\">\n    <button @click=\"toggleCompleted\">Toggle completed</button>\n\n    <Panel>\n      <ul class=\"panel-loop-usage__list\">\n        <li #for=\"item in visibleItems()\">{{ item.label }}</li>\n      </ul>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import Panel from \"./Panel.weiv\";\n\n  export interface TodoItem {\n    label: string;\n    completed: boolean;\n  }\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let showCompleted = false;\n  let items: TodoItem[] = [\n    { label: \"Write parser fixtures\", completed: true },\n    { label: \"Implement template binder\", completed: false },\n    { label: \"Test CSS scoping\", completed: false }\n  ];\n\n  function visibleItems() {\n    return items.filter((item) => item.completed === showCompleted);\n  }\n\n  function toggleCompleted() {\n    showCompleted = !showCompleted;\n  }\n</script>\n\n<style>\n  .panel-loop-usage {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .panel-loop-usage__list {\n    padding-left: 1rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 268, 268, 279]);
    expect_section(doc.script, [282, 288, 289, 298, 281, 299, 299, 879, 879, 888]);
    if doc.style is style {
        expect_section(style, [891, 896, 896, 896, 890, 897, 897, 1018, 1018, 1026]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/PanelNestedCardUsage.weiv" {
    const doc = parse("<template>\n  <section class=\"panel-nested-card-usage\">\n    <button @click=\"toggleCardContent\">Toggle nested card content</button>\n\n    <Panel>\n      <Card>\n        <template slot:header>\n          <h2 class=\"panel-nested-card-usage__title\">{{ title }}</h2>\n          <p class=\"panel-nested-card-usage__eyebrow\">{{ eyebrow }}</p>\n        </template>\n\n        <p class=\"panel-nested-card-usage__body\">{{ body }}</p>\n      </Card>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import Card from \"./Card.weiv\";\n  import Panel from \"./Panel.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let title = \"Nested dashboard\";\n  let eyebrow = \"Nested daily overview\";\n  let body = \"Nested projected body\";\n\n  function toggleCardContent() {\n    if (title === \"Nested dashboard\") {\n      title = \"Nested reports\";\n      eyebrow = \"Nested weekly summary\";\n      body = \"Nested projected report body\";\n    } else {\n      title = \"Nested dashboard\";\n      eyebrow = \"Nested daily overview\";\n      body = \"Nested projected body\";\n    }\n  }\n</script>\n\n<style>\n  .panel-nested-card-usage {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .panel-nested-card-usage__title {\n    font-weight: 700;\n  }\n\n  .panel-nested-card-usage__eyebrow {\n    color: #666;\n  }\n\n  .panel-nested-card-usage__body {\n    line-height: 1.5;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 454, 454, 465]);
    expect_section(doc.script, [468, 474, 475, 484, 467, 485, 485, 1055, 1055, 1064]);
    if doc.style is style {
        expect_section(style, [1067, 1072, 1072, 1072, 1066, 1073, 1073, 1329, 1329, 1337]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/PanelToggleUsage.weiv" {
    const doc = parse("<template>\n  <section class=\"panel-toggle-usage\">\n    <button @click=\"toggleMessage\">Toggle message</button>\n\n    <Panel>\n      <p class=\"panel-toggle-usage__message\">{{ message }}</p>\n    </Panel>\n  </section>\n</template>\n\n<script lang=\"ts\">\n  import Panel from \"./Panel.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let message = \"Projected first\";\n\n  function toggleMessage() {\n    message = message === \"Projected first\" ? \"Projected second\" : \"Projected first\";\n  }\n</script>\n\n<style>\n  .panel-toggle-usage {\n    display: grid;\n    gap: 0.75rem;\n  }\n\n  .panel-toggle-usage__message {\n    font-weight: 600;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 211, 211, 222]);
    expect_section(doc.script, [225, 231, 232, 241, 224, 242, 242, 492, 492, 501]);
    if doc.style is style {
        expect_section(style, [504, 509, 509, 509, 503, 510, 510, 636, 636, 644]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/PanelUsage.weiv" {
    const doc = parse("<template>\n  <Panel>\n    <p class=\"panel-usage__message\">{{ props.message }}</p>\n  </Panel>\n</template>\n\n<script lang=\"ts\">\n  import Panel from \"./Panel.weiv\";\n\n  export interface Props {\n    message: string;\n  }\n\n  export let props: Props;\n</script>\n\n<style>\n  .panel-usage__message {\n    font-weight: 600;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 92, 92, 103]);
    expect_section(doc.script, [106, 112, 113, 122, 105, 123, 123, 241, 241, 250]);
    if doc.style is style {
        expect_section(style, [253, 258, 258, 258, 252, 259, 259, 312, 312, 320]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/ReactiveCardUsage.weiv" {
    const doc = parse("<template>\n  <Card>\n    <template slot:header>\n      <h2 data-test=\"header-title\">{{ title }}</h2>\n      <p data-test=\"header-eyebrow\">Updated {{ updateCount }} time(s)</p>\n    </template>\n    <p data-test=\"body\">{{ body }}</p>\n    <button data-test=\"bump\" @click=\"bump\">Bump</button>\n  </Card>\n</template>\n\n<script lang=\"ts\">\n  import Card from \"./Card.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n\n  let title = \"Initial\";\n  let body = \"Body 0\";\n  let updateCount = 0;\n\n  function bump() {\n    updateCount += 1;\n    title = `Bumped ${updateCount}`;\n    body = `Body ${updateCount}`;\n  }\n</script>\n\n<style></style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 295, 295, 306]);
    expect_section(doc.script, [309, 315, 316, 325, 308, 326, 326, 608, 608, 617]);
    if doc.style is style {
        expect_section(style, [620, 625, 625, 625, 619, 626, 626, 626, 626, 634]);
    } else {
        assert(false);
    }
}
test "test/examples/slots/SlotShowcase.weiv" {
    const doc = parse("<template>\n  <main>\n    <section data-test=\"reactive\">\n      <ReactiveCardUsage />\n    </section>\n    <section data-test=\"empty-with-named\">\n      <EmptyStateUsage :heading=\"'Hello'\" />\n    </section>\n    <section data-test=\"empty-fallback\">\n      <EmptyStateFallbackUsage />\n    </section>\n  </main>\n</template>\n\n<script lang=\"ts\">\n  import ReactiveCardUsage from \"./ReactiveCardUsage.weiv\";\n  import EmptyStateUsage from \"./EmptyStateUsage.weiv\";\n  import EmptyStateFallbackUsage from \"./EmptyStateFallbackUsage.weiv\";\n\n  export interface Props {}\n  export let props: Props;\n</script>\n\n<style></style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 301, 301, 312]);
    expect_section(doc.script, [315, 321, 322, 331, 314, 332, 332, 577, 577, 586]);
    if doc.style is style {
        expect_section(style, [589, 594, 594, 594, 588, 595, 595, 595, 595, 603]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/App.weiv" {
    const doc = parse("<template>\n  <main class=\"todomvc-page\">\n    <section class=\"todoapp\">\n      <TodoHeader :title=\"props.title\" @create=\"addTodo\" />\n\n      <section #if=\"todos.length > 0\" class=\"main\">\n        <input :checked=\"isAllCompleted()\" class=\"toggle-all\" @change=\"toggleAll\" type=\"checkbox\" />\n\n        <TodoList\n          :editingId=\"editingId\"\n          :items=\"visibleTodos()\"\n          @cancel-edit=\"cancelEditing\"\n          @destroy=\"destroyTodo\"\n          @save-edit=\"saveTodo\"\n          @start-edit=\"startEditing\"\n          @toggle=\"toggleTodo\"\n        />\n      </section>\n\n      <TodoFooter\n        #if=\"todos.length > 0\"\n        :activeCount=\"activeCount()\"\n        :completedCount=\"completedCount()\"\n        :filter=\"filter\"\n        @clear-completed=\"clearCompleted\"\n        @filter-change=\"setFilter\"\n      />\n    </section>\n  </main>\n</template>\n\n<script lang=\"ts\">\n  import TodoFooter from \"./TodoFooter.weiv\";\n  import TodoHeader from \"./TodoHeader.weiv\";\n  import TodoList from \"./TodoList.weiv\";\n\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export type Filter = \"all\" | \"active\" | \"completed\";\n\n  export interface SavePayload {\n    id: string;\n    text: string;\n  }\n\n  export interface Props {\n    title: string;\n  }\n\n  export let props: Props;\n\n  let nextId = 6;\n  let filter: Filter = \"all\";\n  let editingId = \"\";\n  let todos: Todo[] = [\n    { id: \"1\", title: \"Port TodoMVC into the verification suite\", completed: true },\n    { id: \"2\", title: \"Verify root-owned state updates across nested components\", completed: false },\n    { id: \"3\", title: \"Exercise edit, filter, and clear-completed flows\", completed: false },\n    { id: \"4\", title: \"Keep scoped CSS realistic under a larger tree\", completed: false },\n    { id: \"5\", title: \"Expose the polished preview on the LAN server\", completed: true }\n  ];\n\n  function visibleTodos() {\n    if (filter === \"active\") {\n      return todos.filter((todo) => !todo.completed);\n    }\n    if (filter === \"completed\") {\n      return todos.filter((todo) => todo.completed);\n    }\n    return todos;\n  }\n\n  function activeCount() {\n    return todos.filter((todo) => !todo.completed).length;\n  }\n\n  function completedCount() {\n    return todos.filter((todo) => todo.completed).length;\n  }\n\n  function isAllCompleted() {\n    return todos.length > 0 && completedCount() === todos.length;\n  }\n\n  function addTodo(text: string) {\n    const title = text.trim();\n    if (title.length === 0) {\n      return;\n    }\n\n    todos = [{ id: String(nextId), title, completed: false }, ...todos];\n    nextId += 1;\n  }\n\n  function toggleTodo(todoId: string) {\n    todos = todos.map((todo) =>\n      todo.id === todoId ? { ...todo, completed: !todo.completed } : todo\n    );\n  }\n\n  function destroyTodo(todoId: string) {\n    todos = todos.filter((todo) => todo.id !== todoId);\n    if (editingId === todoId) {\n      editingId = \"\";\n    }\n  }\n\n  function startEditing(todoId: string) {\n    editingId = todoId;\n  }\n\n  function cancelEditing() {\n    editingId = \"\";\n  }\n\n  function saveTodo(payload: SavePayload) {\n    const title = payload.text.trim();\n    if (title.length === 0) {\n      destroyTodo(payload.id);\n      return;\n    }\n\n    todos = todos.map((todo) =>\n      todo.id === payload.id ? { ...todo, title } : todo\n    );\n    editingId = \"\";\n  }\n\n  function setFilter(nextFilter: Filter) {\n    filter = nextFilter;\n  }\n\n  function clearCompleted() {\n    todos = todos.filter((todo) => !todo.completed);\n  }\n\n  function toggleAll() {\n    const shouldComplete = !isAllCompleted();\n    todos = todos.map((todo) => ({ ...todo, completed: shouldComplete }));\n  }\n</script>\n\n<style>\n  .todomvc-page {\n    min-height: 100vh;\n    padding: 0 1rem 4rem;\n    background: #f5f5f5;\n    color: #4d4d4d;\n    font: 14px \"Helvetica Neue\", Helvetica, Arial, sans-serif;\n    line-height: 1.4em;\n    -webkit-font-smoothing: antialiased;\n    -moz-osx-font-smoothing: grayscale;\n  }\n\n  .todoapp {\n    max-width: 550px;\n    margin: 0 auto;\n    margin-top: 170px;\n    position: relative;\n    background: #fff;\n    box-shadow:\n      0 2px 4px 0 rgba(0, 0, 0, 0.2),\n      0 25px 50px 0 rgba(0, 0, 0, 0.1);\n  }\n\n  .main {\n    position: relative;\n    z-index: 2;\n    border-top: 1px solid #e6e6e6;\n  }\n\n  .toggle-all {\n    position: absolute;\n    top: -55px;\n    left: -12px;\n    width: 60px;\n    height: 34px;\n    text-align: center;\n    border: none;\n    -webkit-appearance: none;\n    appearance: none;\n    outline: none;\n  }\n\n  .toggle-all::before {\n    content: \"❯\";\n    padding: 10px 27px;\n    font-size: 22px;\n    color: #e6e6e6;\n  }\n\n  .toggle-all:checked::before {\n    color: #737373;\n  }\n\n  @media (max-width: 640px) {\n    .todomvc-page {\n      padding-inline: 0.5rem;\n    }\n\n    .todoapp {\n      margin-top: 150px;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 837, 837, 848]);
    expect_section(doc.script, [851, 857, 858, 867, 850, 868, 868, 3636, 3636, 3645]);
    if doc.style is style {
        expect_section(style, [3648, 3653, 3653, 3653, 3647, 3654, 3654, 4787, 4787, 4795]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/TodoFooter.weiv" {
    const doc = parse("<template>\n  <footer class=\"todo-footer\">\n    <span class=\"todo-count\"><strong>{{ props.activeCount }}</strong><span class=\"todo-count__suffix\">{{ props.activeCount === 1 ? \" item left\" : \" items left\" }}</span></span>\n    <ul class=\"filters\">\n      <li><button :class=\"filterClass('all')\" @click=\"selectAll\">All</button></li>\n      <li><button :class=\"filterClass('active')\" @click=\"selectActive\">Active</button></li>\n      <li><button :class=\"filterClass('completed')\" @click=\"selectCompleted\">Completed</button></li>\n    </ul>\n    <button #if=\"props.completedCount > 0\" class=\"clear-completed\" @click=\"clearCompleted\">Clear completed</button>\n  </footer>\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    activeCount: number;\n    completedCount: number;\n    filter: string;\n  }\n\n  export let props: Props;\n\n  function filterClass(name: string) {\n    if (props.filter === name) {\n      return \"selected\";\n    }\n    return \"\";\n  }\n\n  function selectAll() {\n    emit(\"filter-change\", \"all\");\n  }\n\n  function selectActive() {\n    emit(\"filter-change\", \"active\");\n  }\n\n  function selectCompleted() {\n    emit(\"filter-change\", \"completed\");\n  }\n\n  function clearCompleted() {\n    emit(\"clear-completed\", null);\n  }\n</script>\n\n<style>\n  .todo-footer {\n    position: relative;\n    height: 20px;\n    padding: 10px 15px;\n    border-top: 1px solid #e6e6e6;\n    color: #777;\n    text-align: center;\n  }\n\n  .todo-footer::before {\n    content: \"\";\n    position: absolute;\n    right: 0;\n    bottom: 0;\n    left: 0;\n    height: 50px;\n    overflow: hidden;\n    box-shadow:\n      0 1px 1px rgba(0, 0, 0, 0.2),\n      0 8px 0 -3px #f6f6f6,\n      0 9px 1px -3px rgba(0, 0, 0, 0.2),\n      0 16px 0 -6px #f6f6f6,\n      0 17px 2px -6px rgba(0, 0, 0, 0.2);\n  }\n\n  .todo-count {\n    float: left;\n    text-align: left;\n  }\n\n  .todo-count strong {\n    font-weight: 300;\n  }\n\n  .filters {\n    position: absolute;\n    right: 0;\n    left: 0;\n    margin: 0;\n    padding: 0;\n    list-style: none;\n  }\n\n  .filters li {\n    display: inline;\n  }\n\n  .filters li button {\n    margin: 3px;\n    padding: 3px 7px;\n    border: 1px solid transparent;\n    border-radius: 3px;\n    background: none;\n    color: inherit;\n    font: inherit;\n    cursor: pointer;\n    text-decoration: none;\n  }\n\n  .filters li button.selected,\n  .filters li button:hover {\n    border-color: rgba(175, 47, 47, 0.1);\n  }\n\n  .filters li button.selected {\n    border-color: rgba(175, 47, 47, 0.2);\n  }\n\n  .clear-completed {\n    position: relative;\n    float: right;\n    line-height: 20px;\n    padding: 0;\n    border: 0;\n    background: none;\n    font: inherit;\n    color: inherit;\n    -webkit-appearance: none;\n    appearance: none;\n    cursor: pointer;\n  }\n\n  @media (max-width: 430px) {\n    .todo-footer {\n      height: auto;\n      padding-bottom: 48px;\n    }\n\n    .filters {\n      position: static;\n      display: block;\n      margin-top: 8px;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 658, 658, 669]);
    expect_section(doc.script, [672, 678, 679, 688, 671, 689, 689, 1225, 1225, 1234]);
    if doc.style is style {
        expect_section(style, [1237, 1242, 1242, 1242, 1236, 1243, 1243, 2902, 2902, 2910]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/TodoHeader.weiv" {
    const doc = parse("<template>\n  <header class=\"todo-header\">\n    <h1>{{ props.title || \"todos\" }}</h1>\n    <TodoTextInput :initialValue=\"''\" :placeholder=\"'What needs to be done?'\" @submit=\"handleCreate\" />\n  </header>\n</template>\n\n<script lang=\"ts\">\n  import TodoTextInput from \"./TodoTextInput.weiv\";\n\n  export interface Props {\n    title: string;\n  }\n\n  export let props: Props;\n\n  function handleCreate(text: string) {\n    emit(\"create\", text);\n  }\n</script>\n\n<style>\n  .todo-header {\n    position: relative;\n  }\n\n  .todo-header h1 {\n    position: absolute;\n    top: -155px;\n    width: 100%;\n    margin: 0;\n    font-size: 100px;\n    font-weight: 100;\n    text-align: center;\n    text-rendering: optimizeLegibility;\n    color: rgba(175, 47, 47, 0.15);\n  }\n\n  @media (max-width: 640px) {\n    .todo-header h1 {\n      top: -125px;\n      font-size: 76px;\n    }\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 200, 200, 211]);
    expect_section(doc.script, [214, 220, 221, 230, 213, 231, 231, 434, 434, 443]);
    if doc.style is style {
        expect_section(style, [446, 451, 451, 451, 445, 452, 452, 845, 845, 853]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/TodoItem.weiv" {
    const doc = parse("<template>\n  <li :class=\"itemClass()\">\n    <TodoTextInput #if=\"props.editing\" autofocus :editing=\"true\" :initialValue=\"props.todo.title\" :placeholder=\"'Edit task'\" @cancel=\"handleCancel\" @submit=\"handleSubmit\" />\n\n    <div #else class=\"view\">\n      <input :checked=\"props.todo.completed\" class=\"toggle\" @change=\"handleToggle\" type=\"checkbox\" />\n      <label @dblclick=\"startEdit\">{{ props.todo.title }}</label>\n      <button class=\"destroy\" @click=\"handleDestroy\"></button>\n    </div>\n  </li>\n</template>\n\n<script lang=\"ts\">\n  import TodoTextInput from \"./TodoTextInput.weiv\";\n\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export interface Props {\n    todo: Todo;\n    editing: boolean;\n  }\n\n  export let props: Props;\n\n  function itemClass() {\n    if (props.editing) {\n      return \"editing\";\n    }\n    if (props.todo.completed) {\n      return \"completed\";\n    }\n    return null;\n  }\n\n  function startEdit() {\n    emit(\"start-edit\", props.todo.id);\n  }\n\n  function handleToggle() {\n    emit(\"toggle\", props.todo.id);\n  }\n\n  function handleDestroy() {\n    emit(\"destroy\", props.todo.id);\n  }\n\n  function handleSubmit(text: string) {\n    emit(\"save-edit\", { id: props.todo.id, text });\n  }\n\n  function handleCancel() {\n    emit(\"cancel-edit\", null);\n  }\n</script>\n\n<style>\n  li {\n    position: relative;\n    font-size: 24px;\n    border-bottom: 1px solid #ededed;\n  }\n\n  li:last-child {\n    border-bottom: none;\n  }\n\n  li.editing {\n    border-bottom: none;\n    padding: 0;\n  }\n\n  li.editing .view {\n    display: none;\n  }\n\n  .view {\n    display: grid;\n    grid-template-columns: 40px 1fr 40px;\n    align-items: center;\n    column-gap: 8px;\n    min-height: 58px;\n    padding: 0 10px 0 6px;\n  }\n\n  .toggle {\n    position: relative;\n    width: 28px;\n    height: 28px;\n    margin: 0 auto;\n    border: none;\n    border-radius: 50%;\n    background: #fff;\n    box-shadow: inset 0 0 0 2px #ededed;\n    -webkit-appearance: none;\n    appearance: none;\n    outline: none;\n    cursor: pointer;\n  }\n\n  .toggle::after {\n    content: \"\";\n    position: absolute;\n    top: 4px;\n    left: 9px;\n    width: 7px;\n    height: 13px;\n    border-right: 2px solid transparent;\n    border-bottom: 2px solid transparent;\n    transform: rotate(45deg);\n  }\n\n  .toggle:checked::after {\n    border-color: #5dc2af;\n  }\n\n  .toggle:checked {\n    box-shadow: inset 0 0 0 2px #bddad5;\n  }\n\n  label {\n    display: block;\n    margin: 0;\n    padding: 15px 12px 15px 0;\n    line-height: 1.2;\n    white-space: pre-line;\n    word-break: break-all;\n    transition: color 0.4s;\n  }\n\n  li.completed label {\n    color: #d9d9d9;\n    text-decoration: line-through;\n  }\n\n  .destroy {\n    display: none;\n    width: 32px;\n    height: 32px;\n    margin: 0 0 0 auto;\n    padding: 0;\n    border: 0;\n    background: none;\n    color: #cc9a9a;\n    font: inherit;\n    font-size: 30px;\n    line-height: 1;\n    -webkit-appearance: none;\n    appearance: none;\n    cursor: pointer;\n    transition: color 0.2s ease-out;\n  }\n\n  .destroy:hover {\n    color: #af5b5e;\n  }\n\n  .destroy::after {\n    content: \"×\";\n  }\n\n  li:hover .destroy {\n    display: block;\n  }\n\n  @media (max-width: 640px) {\n    .destroy {\n      display: block;\n    }\n  }\n\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 493, 493, 504]);
    expect_section(doc.script, [507, 513, 514, 523, 506, 524, 524, 1299, 1299, 1308]);
    if doc.style is style {
        expect_section(style, [1311, 1316, 1316, 1316, 1310, 1317, 1317, 3217, 3217, 3225]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/TodoList.weiv" {
    const doc = parse("<template>\n  <ul class=\"todo-list\">\n    <TodoItem\n      #for=\"item in props.items\"\n      :editing=\"props.editingId === item.id\"\n      :todo=\"item\"\n      @cancel-edit=\"emitCancel\"\n      @destroy=\"emitDestroy\"\n      @save-edit=\"emitSave\"\n      @start-edit=\"emitStartEdit\"\n      @toggle=\"emitToggle\"\n    />\n  </ul>\n</template>\n\n<script lang=\"ts\">\n  import TodoItem from \"./TodoItem.weiv\";\n\n  export interface Todo {\n    id: string;\n    title: string;\n    completed: boolean;\n  }\n\n  export interface SavePayload {\n    id: string;\n    text: string;\n  }\n\n  export interface Props {\n    items: Todo[];\n    editingId: string;\n  }\n\n  export let props: Props;\n\n  function emitToggle(todoId: string) {\n    emit(\"toggle\", todoId);\n  }\n\n  function emitDestroy(todoId: string) {\n    emit(\"destroy\", todoId);\n  }\n\n  function emitStartEdit(todoId: string) {\n    emit(\"start-edit\", todoId);\n  }\n\n  function emitSave(payload: SavePayload) {\n    emit(\"save-edit\", payload);\n  }\n\n  function emitCancel() {\n    emit(\"cancel-edit\", null);\n  }\n</script>\n\n<style>\n  .todo-list {\n    margin: 0;\n    padding: 0;\n    list-style: none;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 312, 312, 323]);
    expect_section(doc.script, [326, 332, 333, 342, 325, 343, 343, 1021, 1021, 1030]);
    if doc.style is style {
        expect_section(style, [1033, 1038, 1038, 1038, 1032, 1039, 1039, 1112, 1112, 1120]);
    } else {
        assert(false);
    }
}
test "test/examples/todomvc/TodoTextInput.weiv" {
    const doc = parse("<template>\n  <input autofocus :class=\"inputClass()\" :placeholder=\"props.placeholder\" :value=\"props.initialValue || ''\" @blur=\"handleBlur\" @keydown=\"handleKeydown\" type=\"text\" />\n</template>\n\n<script lang=\"ts\">\n  export interface Props {\n    initialValue: string;\n    placeholder: string;\n    editing: boolean;\n  }\n\n  export let props: Props;\n  let suppressBlurSubmit = false;\n\n  function inputClass() {\n    if (props.editing) {\n      return \"edit\";\n    }\n    return \"newtodo\";\n  }\n\n  function readValue(event: any) {\n    return String(event.target.value || \"\").trim();\n  }\n\n  function handleBlur(event: any) {\n    if (props.editing && !suppressBlurSubmit) {\n      emit(\"submit\", readValue(event));\n    }\n    suppressBlurSubmit = false;\n  }\n\n  function handleKeydown(event: any) {\n    if (event.key === \"Enter\") {\n      suppressBlurSubmit = true;\n      emit(\"submit\", readValue(event));\n      return;\n    }\n\n    if (event.key === \"Escape\") {\n      suppressBlurSubmit = true;\n      emit(\"cancel\", null);\n    }\n  }\n</script>\n\n<style>\n  input {\n    position: relative;\n    width: 100%;\n    margin: 0;\n    color: inherit;\n    font-family: inherit;\n    font-weight: inherit;\n    line-height: 1.4em;\n    box-sizing: border-box;\n    -webkit-font-smoothing: antialiased;\n    outline: none;\n    border: 1px solid #999;\n    box-shadow: inset 0 -1px 5px 0 rgba(0, 0, 0, 0.2);\n  }\n\n  .newtodo,\n  .edit {\n    outline: none;\n    font-size: 24px;\n  }\n\n  .newtodo {\n    padding: 16px 16px 16px 60px;\n    border: none;\n    background: rgba(0, 0, 0, 0.003);\n    box-shadow: inset 0 -2px 1px rgba(0, 0, 0, 0.03);\n  }\n\n  .edit {\n    display: block;\n    width: calc(100% - 43px);\n    margin: 0 0 0 43px;\n    padding: 13px 17px 12px;\n  }\n\n  input::placeholder {\n    font-style: italic;\n    font-weight: 300;\n    color: #e6e6e6;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 178, 178, 189]);
    expect_section(doc.script, [192, 198, 199, 208, 191, 209, 209, 1012, 1012, 1021]);
    if doc.style is style {
        expect_section(style, [1024, 1029, 1029, 1029, 1023, 1030, 1030, 1809, 1809, 1817]);
    } else {
        assert(false);
    }
}
test "test/examples/wui-phase1/App.weiv" {
    const doc = parse("<template>\n  <main class=\"app\">\n    <h1>Wui Phase 1 Demo</h1>\n\n    <WuiDialog :triggerLabel=\"'Open release notes'\" :title=\"'Release Notes'\" :description=\"'Summary of this sprint output.'\" :closeLabel=\"'Done'\">\n      <ul class=\"app__list\">\n        <li>Dialog controller semantics now live in ui-core.</li>\n        <li>Public API is now Wui-prefixed Weiv components.</li>\n      </ul>\n    </WuiDialog>\n\n    <WuiDisclosure :label=\"'Toggle deployment details'\" :initialExpanded=\"true\">\n      <p>Deployment window: 02:00 - 03:00 UTC.</p>\n    </WuiDisclosure>\n\n    <WuiTabs :initialTab=\"'Overview'\" :activationMode=\"'automatic'\">\n      <template slot:overview>\n        <p>Overview slot content.</p>\n      </template>\n      <template slot:activity>\n        <p>Activity slot content.</p>\n      </template>\n      <template slot:settings>\n        <p>Settings slot content.</p>\n      </template>\n    </WuiTabs>\n  </main>\n</template>\n\n<script lang=\"ts\">\n  import WuiDialog from \"../../../packages/ui-components/src/WuiDialog.weiv\";\n  import WuiDisclosure from \"../../../packages/ui-components/src/WuiDisclosure.weiv\";\n  import WuiTabs from \"../../../packages/ui-components/src/WuiTabs.weiv\";\n\n  export interface Props {}\n\n  export let props: Props;\n</script>\n\n<style>\n  .app {\n    display: grid;\n    gap: 1rem;\n    max-width: 680px;\n    margin: 1.5rem auto;\n    font-family: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif;\n  }\n\n  .app__list {\n    margin: 0;\n    padding-left: 1.1rem;\n  }\n</style>\n".bytes()) catch (code) {
        assert(false);
        return;
    };
    expect_section(doc.template, [1, 9, 9, 9, 0, 10, 10, 909, 909, 920]);
    expect_section(doc.script, [923, 929, 930, 939, 922, 940, 940, 1236, 1236, 1245]);
    if doc.style is style {
        expect_section(style, [1248, 1253, 1253, 1253, 1247, 1254, 1254, 1483, 1483, 1491]);
    } else {
        assert(false);
    }
}
