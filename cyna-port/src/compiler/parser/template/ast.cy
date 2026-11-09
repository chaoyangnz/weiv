// Model: raw template nodes, attributes and directives; all text uses source spans.
import { Span } from .compiler.source;

pub struct TemplateAttribute {
    pub name: Span;
    pub value: ?Span;
    pub span: Span;
}

pub struct TemplateElement {
    pub tag_name: Span;
    pub attributes_start: usize;
    pub attributes_count: usize;
    pub directives_start: usize;
    pub directives_count: usize;
}

pub union TemplatePayload {
    element: TemplateElement;
    text: Span;
    interpolation: Span;
    slot_outlet: TemplateSlotOutlet;
}

pub struct TemplateNode {
    pub span: Span;
    pub payload: TemplatePayload;
    // Exclusive preorder boundary; the next sibling has this ID.
    pub subtree_end: usize;
}

pub struct TemplateDocument {
    pub nodes: List<TemplateNode>;
    pub attributes: List<TemplateAttribute>;
    pub directives: List<TemplateDirective>;
}

pub struct TemplateFor {
    pub item_name: Span;
    pub iterable_expr: Span;
}

pub struct TemplateExpressionTarget {
    pub name: Span;
    pub expression: Span;
    pub deprecated_syntax: bool;
}

pub union TemplateDirectivePayload {
    if_expr: Span;
    else_branch;
    for_expr: TemplateFor;
    event: TemplateExpressionTarget;
    bind: TemplateExpressionTarget;
    slot_assign: Span;
}

pub struct TemplateDirective {
    pub span: Span;
    pub payload: TemplateDirectivePayload;
}

pub struct TemplateSlotOutlet {
    pub name: ?Span;
    pub attributes_start: usize;
    pub attributes_count: usize;
}
