// Models: project-owned source files and local component import edges.
pub struct ComponentNode {
    pub path: string;
    pub source: string;
    pub module_path: string;
}

pub struct ComponentImport {
    pub importer_path: string;
    pub target_path: string;
    pub source: string;
    pub local_name: string;
}

pub struct ComponentGraph {
    pub root_dir: string;
    pub entry_path: string;
    pub nodes: List<ComponentNode>;
    pub imports: List<ComponentImport>;

    pub fn find_node(self: &const ComponentGraph, path: string): ?usize {
        var i: usize = 0;
        while i < self.nodes.len() {
            if self.nodes[i].path == path {
                return i;
            }
            i = i + 1;
        }
        return none;
    }
}
