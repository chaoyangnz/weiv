// Model: typed emission-only evaluator identity and source provenance; no rewritten tree.
import { Span } from .compiler.source;
pub enum EvaluatorArgument {
    render;
    event;
    payload;
}
pub enum EvaluatorSite {
    interpolation;
    condition;
    iterable;
    binding;
    handler;
}
pub struct EvaluatorRecord {
    // Zero-based ID in the emitted __weiv_eval array; distinct from one-based region IDs.
    pub id: usize;
    pub node_id: usize;
    // Zero for node expressions; index within bind_effects/event_effects otherwise.
    pub effect_index: usize;
    pub site: EvaluatorSite;
    pub argument: EvaluatorArgument;
    pub template: Span;
    pub generated: Span;
}
pub struct EvaluatorPlan {
    // Comma-separated closures, passed to Rust lowering with the original script.
    pub code: string;
    pub records: List<EvaluatorRecord>;
    pub fn find(self: &const EvaluatorPlan, node_id: usize, site: EvaluatorSite, effect_index: usize): ?usize {
        var i: usize = 0;
        while i < self.records.len() {
            const record = &self.records[i];
            if record.node_id == node_id and record.site == site and record.effect_index == effect_index {
                return i;
            }
            i = i + 1;
        }
        return none;
    }
}
