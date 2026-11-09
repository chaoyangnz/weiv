// Operation: source + paired raw/normalized templates -> detached slot manifest report.
import { TemplateDocument, TemplateSlotOutlet } from .compiler.parser.template.ast;
import { NormalizedDocument } from .compiler.parser.template.normalized;
import { SlotEntry, SlotDuplicate, SlotManifest, SlotManifestReport } from .compiler.sema.slot_manifest;

pub fn build(source: []const u8, raw: &const TemplateDocument, normalized: &const NormalizedDocument): SlotManifestReport {
    var manifest: SlotManifest = {
        entries: list<SlotEntry>()
    };
    var duplicates = list<SlotDuplicate>();
    var id: usize = 0;
    while id < normalized.nodes.len() {
        const node = normalized.nodes[id];
        switch node.payload {
            .slot_outlet(raw_id) => {
                const outlet: TemplateSlotOutlet = switch raw.nodes[raw_id].payload {
                    .slot_outlet(value) => value;
                    _ => {
                        panic("Normalized slot must reference its raw outlet");
                    }
                };
                var name: ?string = none;
                if outlet.name is span {
                    name = string.from(source[span.start..span.end]);
                }
                var duplicate = false;
                if name is text {
                    duplicate = manifest.has_name(text);
                } else {
                    duplicate = manifest.has_default();
                }
                if duplicate {
                    duplicates.push(SlotDuplicate {
                        name: name,
                        span: node.span
                    });
                }
                manifest.entries.push(SlotEntry {
                    name: name,
                    span: node.span
                });
                // Fallback content is not part of the component's public slot manifest.
                id = node.subtree_end;
            }
            _ => {
                id = id + 1;
            }
        }
    }
    return {
        manifest: manifest,
        duplicates: duplicates
    };
}
