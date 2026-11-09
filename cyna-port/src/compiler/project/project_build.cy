// Models: owned project browser output and its relative module artifacts.
import { ProjectDiagnostic } from .compiler.project.diagnostics;

pub struct ProjectModule {
    pub source_path: string;
    pub module_path: string;
    pub code: string;
    pub css: string;
}

pub struct ProjectBuild {
    pub entry_module: string;
    pub modules: List<ProjectModule>;
    pub stylesheet: string;
    pub diagnostics: List<ProjectDiagnostic>;
}
