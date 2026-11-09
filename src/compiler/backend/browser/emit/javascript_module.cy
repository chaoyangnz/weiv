// Models: emitter import mapping inputs and independently owned JavaScript artifact.
pub struct ImportOverride {
    pub source: string;
    pub target: string;
}
pub struct JavaScriptModule {
    pub code: string;
    pub scope_id: string;
    pub css: string;
}
