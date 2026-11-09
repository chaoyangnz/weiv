// Operation: fragment-relative diagnostic -> checked full-file byte span.
import { Span } from .compiler.source;
import { ComponentCompileReport } from .compiler.component_unit;
import { CompilationDiagnostic, SourceOrigin } from .compiler.diagnostics;

pub fn map_span(report: &const ComponentCompileReport, diagnostic: &const CompilationDiagnostic): ?Span {
    if diagnostic.span is local {
        var base: usize = 0;
        var length = report.source.bytes().len();
        if diagnostic.origin != SourceOrigin.file {
            if report.sfc_document is sfc {
                const section = switch diagnostic.origin {
                    SourceOrigin.template => sfc.template.content_span;
                    SourceOrigin.script => sfc.script.content_span;
                    SourceOrigin.file => {
                        panic("File origin already handled");
                    }
                };
                base = section.start;
                length = section.end - section.start;
            } else {
                return none;
            }
        }
        if local.start > local.end or local.end > length {
            return none;
        }
        const result: ?Span = Span {
            start: base + local.start,
            end: base + local.end
        };
        return result;
    }
    return none;
}
