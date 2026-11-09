// Operation: raw attributes -> ordinary attributes and recognized directive records.
import { Span } from .compiler.source;
import { TemplateAttribute, TemplateDocument, TemplateDirective, TemplateDirectivePayload, TemplateFor, TemplateExpressionTarget } from .compiler.parser.template.ast;
import { TemplateParseError } from .compiler.parser.template.errors;
import .compiler.parser.template.scan;

fn required_value(attribute: TemplateAttribute): Span ! TemplateParseError {
    if attribute.value is value {
        return value;
    }
    throw TemplateParseError.invalid_directive;
}

fn classify(source: []const u8, attribute: TemplateAttribute): ?TemplateDirectivePayload ! TemplateParseError {
    const name = attribute.name;
    if scan.equals(source, name, "#if") {
        const result: TemplateDirectivePayload = .if_expr(try required_value(attribute));
        const optional_result: ?TemplateDirectivePayload = result;
        return optional_result;
    }
    if scan.equals(source, name, "#else") {
        if attribute.value is value {
            throw TemplateParseError.invalid_directive;
        }
        const result: TemplateDirectivePayload = .else_branch;
        const optional_result: ?TemplateDirectivePayload = result;
        return optional_result;
    }
    if scan.equals(source, name, "#for") {
        const value = try required_value(attribute);
        const marker = scan.find(source, value, " in ");
        if marker is none {
            throw TemplateParseError.invalid_directive;
        }
        const item = scan.trim(source, value.start, marker);
        const iterable = scan.trim(source, marker + 4, value.end);
        if item.start == item.end or iterable.start == iterable.end {
            throw TemplateParseError.invalid_directive;
        }
        const result: TemplateDirectivePayload = .for_expr(TemplateFor {
            item_name: item,
            iterable_expr: iterable
        });
        const optional_result: ?TemplateDirectivePayload = result;
        return optional_result;
    }
    var prefix: usize = 0;
    var event = false;
    var binding = false;
    var deprecated = false;
    if scan.starts_with(source, name.start, "on:") {
        prefix = 3;
        event = true;
        deprecated = true;
    } else if scan.starts_with(source, name.start, "@") {
        prefix = 1;
        event = true;
    } else if scan.starts_with(source, name.start, "bind:") {
        prefix = 5;
        binding = true;
        deprecated = true;
    } else if scan.starts_with(source, name.start, ":") {
        prefix = 1;
        binding = true;
    }
    if event or binding {
        const value = try required_value(attribute);
        const target: Span = {
            start: name.start + prefix,
            end: name.end
        };
        if not deprecated and target.start == target.end {
            throw TemplateParseError.invalid_directive;
        }
        const payload: TemplateExpressionTarget = {
            name: target,
            expression: value,
            deprecated_syntax: deprecated
        };
        if event {
            const result: TemplateDirectivePayload = .event(payload);
            const optional_result: ?TemplateDirectivePayload = result;
            return optional_result;
        }
        const result: TemplateDirectivePayload = .bind(payload);
        const optional_result: ?TemplateDirectivePayload = result;
        return optional_result;
    }
    if scan.starts_with(source, name.start, "slot:") {
        if attribute.value is value {
            throw TemplateParseError.invalid_directive;
        }
        const target: Span = {
            start: name.start + 5,
            end: name.end
        };
        if target.start == target.end {
            throw TemplateParseError.invalid_directive;
        }
        const result: TemplateDirectivePayload = .slot_assign(target);
        const optional_result: ?TemplateDirectivePayload = result;
        return optional_result;
    }
    const absent: ?TemplateDirectivePayload = none;
    return absent;
}

pub fn split(source: []const u8, raw: []const TemplateAttribute, document: &TemplateDocument): void ! TemplateParseError {
    for attribute in raw {
        const payload = try classify(source, attribute);
        if payload is directive {
            document.directives.push(TemplateDirective {
                span: attribute.span,
                payload: directive
            });
        } else {
            document.attributes.push(attribute);
        }
    }
    return;
}
