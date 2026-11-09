// Model: target-neutral LIR; owned edges/records and spans in one retained source snapshot.
import { Span } from .compiler.source;

pub struct LirAttribute {
    pub name: Span;
    pub value: ?Span;
}
pub struct LirEffectTarget {
    pub name: Span;
    pub expression: Span;
}
pub union LirDirectiveEffect {
    event: LirEffectTarget;
    bind: LirEffectTarget;
}
pub struct LirExpressionReference {
    pub name: string;
    pub call: bool;
}
pub struct LirExpressionFacts {
    pub source: Span;
    pub references: List<LirExpressionReference>;
}
pub struct LirElement {
    pub tag_name: Span;
    pub attributes: List<LirAttribute>;
    pub effects: List<LirDirectiveEffect>;
    pub children: List<usize>;
}
pub struct LirConditional {
    pub condition: Span;
    pub consequent: List<usize>;
    pub alternate: List<usize>;
}
pub struct LirForLoop {
    pub item_name: Span;
    pub iterable_expr: Span;
    pub body: List<usize>;
}
pub struct LirSlotProvision {
    pub name: ?Span;
    pub children: List<usize>;
}
pub struct LirComponent {
    pub tag_name: Span;
    pub effects: List<LirDirectiveEffect>;
    pub slot_provisions: List<LirSlotProvision>;
}
pub struct LirSlotOutlet {
    pub name: ?Span;
    pub fallback_children: List<usize>;
}
pub union LirPayload {
    element: LirElement;
    text: Span;
    interpolation: Span;
    conditional: LirConditional;
    for_loop: LirForLoop;
    component: LirComponent;
    slot_outlet: LirSlotOutlet;
}
pub struct LirNode {
    pub span: Span;
    pub payload: LirPayload;
}
pub struct LirDocument {
    // Frontend invariant: roots/child/provision edges form a forest reaching each node exactly once.
    pub nodes: List<LirNode>;
    pub roots: List<usize>;
    pub expressions: List<LirExpressionFacts>;

    pub fn find_expression(self: &const LirDocument, source: Span): ?usize {
        var i: usize = 0;
        while i < self.expressions.len() {
            const expression = &self.expressions[i];
            if expression.source.start == source.start and expression.source.end == source.end {
                return i;
            }
            i = i + 1;
        }
        return none;
    }
}
