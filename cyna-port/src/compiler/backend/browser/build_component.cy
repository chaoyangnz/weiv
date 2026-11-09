// Coordinator operation: consume a complete unit and construct browser planning artifacts.
import { ComponentUnit } from .compiler.component_unit;
import { BrowserComponent } from .compiler.backend.browser.component;
import { lower } from .compiler.backend.browser.render_tree.lower;
import { build as build_regions } from .compiler.backend.browser.build_region_graph;

pub fn build(unit: ComponentUnit): BrowserComponent {
    const tree = lower(&unit.lir_document);
    const bytes = unit.source.bytes();
    const template = bytes[unit.sfc_document.template.content_span.start..unit.sfc_document.template.content_span.end];
    const graph = build_regions(template, &unit.script.facts, &unit.lir_document, &tree);
    return {
        unit: unit,
        render_tree: tree,
        region_graph: graph
    };
}
