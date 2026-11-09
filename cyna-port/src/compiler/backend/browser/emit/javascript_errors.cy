// Shared emission failure contract; no persistent compiler data.
pub enum JavaScriptError {
    unsupported_template;
    unsupported_render_expression;
    unsupported_handler_expression;
    reserved_evaluator_identifier;
    evaluator_plan_mismatch;
    region_graph_mismatch;
    unterminated_rule;
    backend_failure;
    invalid_backend_response;
    cell_assignment_pattern_unsupported;
    cell_var_declaration_unsupported;
    cell_dynamic_eval_unsupported;
    cell_top_level_await_unsupported;
    cell_ambient_declaration_unsupported;
    cell_const_assignment_unsupported;
    cell_reserved_identifier;
    cell_template_untracked_assignment_unsupported;
    cell_component_default_export_unsupported;
    cell_declaration_unsupported;
}
