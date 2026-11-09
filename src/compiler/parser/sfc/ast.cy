// Model: top-level SFC section ranges in one immutable source snapshot.
import { Span } from .compiler.source;

pub struct SfcSection {
    pub tag_name: Span;
    pub attributes: Span;
    pub open_span: Span;
    pub content_span: Span;
    pub close_span: Span;
}

pub struct SfcDocument {
    pub template: SfcSection;
    pub script: SfcSection;
    pub style: ?SfcSection;
}
