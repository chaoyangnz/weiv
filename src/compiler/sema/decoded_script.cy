// Model: decoded backend result; semantic facts and emitted code have separate fields.
import { ScriptFacts } from .compiler.sema.script_facts;

pub struct DecodedScript {
    pub facts: ScriptFacts;
    pub transpiled_code: string;
}
