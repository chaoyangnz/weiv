// Model: stable encounter-ordered dependency names, independently owned.
pub struct DependencyList {
    pub items: List<string>;

    pub fn contains(self: &const DependencyList, name: string): bool {
        var i: usize = 0;
        while i < self.items.len() {
            if self.items[i] == name {
                return true;
            }
            i = i + 1;
        }
        return false;
    }
}
