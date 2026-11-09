// Model: caller-selected local cells and their dirty-binding subscriptions.
pub struct LocalSubscription {
    pub name: string;
    pub binding: string;
    pub publisher_backed: bool;
}

pub struct ManagedSubscription {
    pub specifier: string;
    pub name: string;
    pub binding: string;
}

pub struct CellSelection {
    pub local_names: List<string>;
    pub local_subscriptions: List<LocalSubscription>;
    pub managed_subscriptions: List<ManagedSubscription>;
}

pub fn empty(): CellSelection {
    return {
        local_names: list<string>(),
        local_subscriptions: list<LocalSubscription>(),
        managed_subscriptions: list<ManagedSubscription>()
    };
}
