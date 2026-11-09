// Model: detached slot names, outlet locations and duplicate reports.
import { Span } from .compiler.source;

pub struct SlotEntry {
    // none means default; an empty string is an explicitly named slot.
    pub name: ?string;
    pub span: Span;
}

pub struct SlotDuplicate {
    pub name: ?string;
    pub span: Span;
}

pub struct SlotManifest {
    pub entries: List<SlotEntry>;

    // Indexed borrows preserve name lifetimes; see Cyna LG-58.
    pub fn has_default(self: &const SlotManifest): bool {
        var index: usize = 0;
        while index < self.entries.len() {
            const entry = &self.entries[index];
            if entry.name is none {
                return true;
            }
            index = index + 1;
        }
        return false;
    }

    pub fn has_name(self: &const SlotManifest, name: string): bool {
        var index: usize = 0;
        while index < self.entries.len() {
            const entry = &self.entries[index];
            if entry.name is actual {
                if actual == name {
                    return true;
                }
            }
            index = index + 1;
        }
        return false;
    }
}

pub struct SlotManifestReport {
    pub manifest: SlotManifest;
    pub duplicates: List<SlotDuplicate>;
}
