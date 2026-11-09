// Model: imported component slot facts supplied before binding; lookup returns stable IDs.
import { SlotManifest } from .compiler.sema.slot_manifest;

pub struct ComponentSlotManifest {
    pub tag_name: string;
    pub manifest: SlotManifest;
}

pub struct ComponentManifests {
    pub entries: List<ComponentSlotManifest>;

    pub fn find(self: &const ComponentManifests, tag_name: string): ?usize {
        var i: usize = 0;
        while i < self.entries.len() {
            const entry = &self.entries[i];
            if entry.tag_name == tag_name {
                return i;
            }
            i = i + 1;
        }
        return none;
    }
}
