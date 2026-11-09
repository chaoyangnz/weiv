// Model: direct browser update regions and their independently owned path inventory.
import { Span } from .compiler.source;
import { TrackedPaths } from .compiler.backend.browser.tracked_paths;

pub enum RegionKind {
    text;
    attribute;
    conditional;
    loop;
    child;
    slot;
}
pub fn region_kind_label(kind: RegionKind): string {
    return switch kind {
        RegionKind.text => "text";
        RegionKind.attribute => "attribute";
        RegionKind.conditional => "conditional";
        RegionKind.loop => "loop";
        RegionKind.child => "child";
        RegionKind.slot => "slot";
    };
}
pub struct Region {
    // Region IDs are one-based encounter order; ref IDs come from the render tree.
    pub id: usize;
    pub kind: RegionKind;
    pub ref_id: usize;
    pub name: ?string;
    pub dependency_names: List<string>;
    pub tracked_path_ids: List<usize>;
    pub precise_import_name: ?string;
    // Extra provenance: originating render/LIR node ID and template-relative source range.
    pub node_id: usize;
    pub span: Span;
}
pub struct RegionGraph {
    pub table: TrackedPaths;
    pub regions: List<Region>;

    // Checked conversion from a one-based region ID to a zero-based collection index.
    pub fn region_index(self: &const RegionGraph, id: usize): ?usize {
        if id == 0 or id > self.regions.len() {
            return none;
        }
        return id - 1;
    }
}
