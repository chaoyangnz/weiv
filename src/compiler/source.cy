// Half-open UTF-8 byte range in the caller's immutable source snapshot.
pub struct Span {
    pub start: usize;
    pub end: usize;
}
