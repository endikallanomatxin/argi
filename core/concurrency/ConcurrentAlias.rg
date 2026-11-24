-- The nominal owner vouches for simultaneous use of its concurrent interface.
-- This marker alone grants no reference, transfer, or cleanup authority.
ConcurrentAlias#(.T: Type): Contract = ()

-- Retire this owner's shared generation after all execution loans complete.
recover_ordinary := #(.T: Type) (.owner: $&T) -> () {}

-- Only the nominal owner's module may invoke this representation boundary.
trusted_concurrent_view := #(.T: Type) (.shared: $$&T) -> (.view: &T) {
    view = __concurrent_representation(.shared = shared)
}
