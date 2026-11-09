// Model: browser-trackable binding kinds and owned root records.
pub enum TrackedKind {
    imported_tracked;
    prop_tracked;
    local_tracked;

}
pub fn kind_label(kind: TrackedKind): string {
    return switch kind {
        TrackedKind.imported_tracked => "imported-tracked";
        TrackedKind.prop_tracked => "prop-tracked";
        TrackedKind.local_tracked => "local-tracked";
    };
}
pub struct TrackedRoot {
    pub id: usize;
    pub binding_name: string;
    pub kind: TrackedKind;
}
