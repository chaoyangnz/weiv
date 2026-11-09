// Model: browser node references, split effects and owned child edges; text uses source spans.
import { Span } from .compiler.source;
import { LirAttribute, LirDirectiveEffect } from .compiler.lower.lir;

pub struct RenderInterpolation {
    pub ref_id: usize;
    pub expression: Span;
}
pub struct RenderElement {
    pub ref_id: usize;
    pub tag_name: Span;
    pub attributes: List<LirAttribute>;
    pub bind_effects: List<LirDirectiveEffect>;
    pub event_effects: List<LirDirectiveEffect>;
    pub children: List<usize>;
}
pub struct RenderConditional {
    pub condition: Span;
    pub start_ref_id: usize;
    pub end_ref_id: usize;
    pub state_ref_id: usize;
    pub consequent: List<usize>;
    pub alternate: List<usize>;
}
pub struct RenderForLoop {
    pub item_name: Span;
    pub iterable_expr: Span;
    pub start_ref_id: usize;
    pub end_ref_id: usize;
    pub state_ref_id: usize;
    pub body: List<usize>;
}
pub struct RenderComponent {
    pub tag_name: Span;
    pub start_ref_id: usize;
    pub end_ref_id: usize;
    pub handle_ref_id: usize;
    pub bind_effects: List<LirDirectiveEffect>;
    pub event_effects: List<LirDirectiveEffect>;
    pub slot_provisions: List<RenderSlotProvision>;
}
pub struct RenderSlotOutlet {
    pub name: ?Span;
    pub start_ref_id: usize;
    pub end_ref_id: usize;
    pub handle_ref_id: usize;
    pub fallback_children: List<usize>;
}
pub struct RenderSlotProvision {
    pub name: ?Span;
    pub children: List<usize>;
}
pub union RenderPayload {
    text: Span;
    interpolation: RenderInterpolation;
    element: RenderElement;
    conditional: RenderConditional;
    for_loop: RenderForLoop;
    component: RenderComponent;
    slot_outlet: RenderSlotOutlet;
}
pub struct RenderNode {
    pub span: Span;
    pub payload: RenderPayload;
}
pub struct RenderDocument {
    // One-to-one node IDs with the originating LIR; all collections are independently owned.
    pub nodes: List<RenderNode>;
    pub roots: List<usize>;
    pub next_ref_id: usize;
}
