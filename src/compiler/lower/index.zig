pub const diagnostic_spans = @import("diagnostic_spans.zig");
pub const lir = @import("lir.zig");
const lower_pass = @import("lower.zig");

pub const LirDocument = lir.Document;

pub const lower = lower_pass.lower;
