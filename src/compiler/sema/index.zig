const bind_pass = @import("bind.zig");
pub const decode_script_facts = @import("decode_script_facts.zig");
pub const sir = @import("sir.zig");
pub const slot_manifest = @import("slot_manifest.zig");

pub const TemplateBindings = sir.TemplateBindings;
pub const ScriptFacts = sir.ScriptFacts;

pub const bind = bind_pass.bind;
