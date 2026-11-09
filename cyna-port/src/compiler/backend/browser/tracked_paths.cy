// Model: owned canonical tracked paths; IDs are one-based and equal to array index + 1.
import { TrackedRoot } from .compiler.backend.browser.tracked_roots;

pub struct TrackedPath {
    pub id: usize;
    pub root_id: usize;
    pub path: string;
    pub parent_path_id: ?usize;
}
pub struct TrackedPaths {
    pub roots: List<TrackedRoot>;
    pub paths: List<TrackedPath>;

    pub fn find_root(self: &const TrackedPaths, name: string): ?usize {
        var i: usize = 0;
        while i < self.roots.len() {
            const root = &self.roots[i];
            if root.binding_name == name {
                return root.id;
            }
            i = i + 1;
        }
        return none;
    }
    pub fn find_path(self: &const TrackedPaths, path: string): ?usize {
        var i: usize = 0;
        while i < self.paths.len() {
            const entry = &self.paths[i];
            if entry.path == path {
                return entry.id;
            }
            i = i + 1;
        }
        return none;
    }
}
