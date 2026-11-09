pub enum TemplateParseError {
    unexpected_close_tag;
    unterminated_tag;
    unterminated_interpolation;
    mismatched_close_tag;
    invalid_directive;
    invalid_slot_outlet;
}
