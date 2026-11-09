// Model: complete browser compilation owner; source spans remain tied to unit.source.
import { ComponentUnit } from .compiler.component_unit;
import { RenderDocument } from .compiler.backend.browser.render_tree.tree;
import { RegionGraph } from .compiler.backend.browser.region_graph;

pub struct BrowserComponent {
    pub unit: ComponentUnit;
    pub render_tree: RenderDocument;
    pub region_graph: RegionGraph;
}
