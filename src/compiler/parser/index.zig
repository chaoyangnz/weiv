pub const sfc = @import("sfc.zig");
pub const template = @import("template/index.zig");

pub const SfcDocument = sfc.Document;
pub const TemplateDocument = template.Document;
pub const NormalizedTemplate = template.NormalizedDocument;

pub const parseSfc = sfc.parse;
pub const parseTemplate = template.parse;
pub const normalizeTemplate = template.normalize;
