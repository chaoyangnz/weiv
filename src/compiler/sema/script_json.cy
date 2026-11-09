// Validate the JSON field contract returned by the retained script backend.
import { Value, Object } from std.json;
import { Span } from .compiler.source;

pub enum ScriptDecodeError {
    invalid_json;
    missing_field;
    wrong_type;
    invalid_integer;
    integer_overflow;
    invalid_span;
}

pub fn required(object: &const Object, key: string): &const Value ! ScriptDecodeError {
    const index = object.find(key);
    if index is none {
        throw ScriptDecodeError.missing_field;
    }
    return &object.members[index].value;
}

pub fn text(value: &const Value): string ! ScriptDecodeError {
    return switch value {
        .string(content) => content;
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

pub fn optional_text(value: &const Value): ?string ! ScriptDecodeError {
    switch value {
        .null_value => {
            const empty: ?string = none;
            return empty;
        }
        .string(content) => {
            const present: ?string = content;
            return present;
        }
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    }
}

pub fn boolean(value: &const Value): bool ! ScriptDecodeError {
    return switch value {
        .bool(flag) => flag;
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
}

pub fn unsigned(value: &const Value, maximum: usize): usize ! ScriptDecodeError {
    const spelling: string = switch value {
        .number(number) => number.spelling;
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    };
    const bytes = spelling.bytes();
    if bytes.len() == 0 {
        throw ScriptDecodeError.invalid_integer;
    }
    var result: usize = 0;
    for byte in bytes {
        if byte < 48 or byte > 57 {
            throw ScriptDecodeError.invalid_integer;
        }
        const digit = (byte - 48) as usize;
        if result > maximum / 10 {
            throw ScriptDecodeError.integer_overflow;
        }
        if result == maximum / 10 and digit > maximum % 10 {
            throw ScriptDecodeError.integer_overflow;
        }
        result = result * 10 + digit;
    }
    return result;
}

pub fn offset_limit(): usize {
    const zero: usize = 0;
    return zero -% 1;
}

pub fn span(object: &const Object, start_key: string, end_key: string): Span ! ScriptDecodeError {
    const start = try unsigned(try required(object, start_key), offset_limit());
    const end = try unsigned(try required(object, end_key), offset_limit());
    if start > end {
        throw ScriptDecodeError.invalid_span;
    }
    return {
        start: start,
        end: end
    };
}

pub fn text_field(object: &const Object, key: string): string ! ScriptDecodeError {
    return try text(try required(object, key));
}

pub fn optional_text_field(object: &const Object, key: string): ?string ! ScriptDecodeError {
    return try optional_text(try required(object, key));
}

pub fn bool_field(object: &const Object, key: string): bool ! ScriptDecodeError {
    return try boolean(try required(object, key));
}

pub fn records<T>(value: &const Value, decode_item: fn (&const Value): T ! ScriptDecodeError): List<T>!ScriptDecodeError {
    var result = list<T>();
    switch value {
        .array(array) => {
            var i: usize = 0;
            while i < array.items.len() {
                result.push(try decode_item(&array.items[i]));
                i = i + 1;
            }
        }
        _ => {
            throw ScriptDecodeError.wrong_type;
        }
    }
    return result;
}

pub fn record_field<T>(object: &const Object, key: string, decode_item: fn (&const Value): T ! ScriptDecodeError): List<T>!ScriptDecodeError {
    return try records<T>(try required(object, key), decode_item);
}

pub fn default_records<T>(object: &const Object, key: string, decode_item: fn (&const Value): T ! ScriptDecodeError): List<T>!ScriptDecodeError {
    const index = object.find(key);
    if index is none {
        return list<T>();
    }
    return try records<T>(&object.members[index].value, decode_item);
}
