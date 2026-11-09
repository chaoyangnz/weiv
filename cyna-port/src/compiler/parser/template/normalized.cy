// Model: normalized template nodes; raw IDs refer to the associated immutable AST.
import { Span } from .compiler.source;

pub struct NormalizedElement {
    pub raw_node: usize;
    pub directives_start: usize;
    pub directives_count: usize;
}

pub struct NormalizedConditional {
    pub condition: Span;
    // Consequent: [wrapper + 1, alternate_start); alternate: [alternate_start, subtree_end).
    pub alternate_start: usize;
}

pub struct NormalizedLoop {
    pub item_name: Span;
    pub iterable_expr: Span;
}

pub union NormalizedPayload {
    element: NormalizedElement;
    text: Span;
    interpolation: Span;
    conditional: NormalizedConditional;
    for_loop: NormalizedLoop;
    slot_outlet: usize;
}

pub struct NormalizedNode {
    pub span: Span;
    pub payload: NormalizedPayload;
    pub subtree_end: usize;
}

pub struct NormalizedDocument {
    pub nodes: List<NormalizedNode>;
    // IDs in the associated immutable raw document's directive arena.
    pub directive_ids: List<usize>;
}
