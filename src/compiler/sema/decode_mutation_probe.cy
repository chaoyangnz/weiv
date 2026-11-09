// Boundary operation: checked mutation-probe JSON -> selection Boolean.
import std.json;
import .compiler.sema.script_json as validation;
pub enum MutationProbeError {
    invalid_response;
}
pub fn decode(payload: string): bool ! MutationProbeError {
    const value = json.parse(payload) catch (code) {
        throw MutationProbeError.invalid_response;
    };
    switch value {
        .object(object) => {
            const ok = validation.bool_field(&object, "ok") catch (code) {
                throw MutationProbeError.invalid_response;
            };
            const index = object.find("bindings");
            if index is none {
                throw MutationProbeError.invalid_response;
            }
            const bindings = &object.members[index].value;
            switch bindings {
                .array(records) => {
                    var first_mutates = false;
                    var i: usize = 0;
                    while i < records.items.len() {
                        const item = &records.items[i];
                        switch item {
                            .object(record) => {
                                const mutates = validation.bool_field(&record, "has_mutation") catch (code) {
                                    throw MutationProbeError.invalid_response;
                                };
                                if i == 0 {
                                    first_mutates = mutates;
                                }
                            }
                            _ => {
                                throw MutationProbeError.invalid_response;
                            }
                        }
                        i = i + 1;
                    }
                    return ok and first_mutates;
                }
                _ => {
                    throw MutationProbeError.invalid_response;
                }
            }
        }
        _ => {
            throw MutationProbeError.invalid_response;
        }
    }
}
