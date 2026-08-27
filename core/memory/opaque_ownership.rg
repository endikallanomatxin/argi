-- Explicit trusted ownership boundaries usable by any library. The checker
-- still enforces every invariant it can prove; callers maintain runtime-slot
-- initializedness and exactly-once destruction manually. In particular,
-- drop_owned requires exactly one live value that has not already been taken
-- or dropped; opaque slots intentionally have no dynamic occupancy tracking.
trusted_opaque_store_owned#(.t: Type)(.destination: $&t, .source: t) -> () := {
    destination& = source
}

-- Storage-aware form. `storage` is the stable structural domain shared by the
-- opaque slots whose contents are summarized together. It has no runtime role;
-- the safety checker uses its Place to retain hidden temporal dependencies.
-- Dependencies are conservative and monotonic for that domain in the current
-- model; mutation through a slot pointer is not tracked yet.
trusted_opaque_store_owned_in#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .destination: $&t, .source: t) -> () := {
    destination& = source
}

-- Moves one live opaque-owned representation between slots. It neither
-- destroys the source representation nor creates precise ownership for the
-- destination. The caller must ensure that `source` is live, `destination`
-- is empty, and the two slots are distinct.
--
-- Passing store_owned once is not a permanent relocatability proof: later
-- mutation through a pointer to an opaque slot can introduce address-sensitive
-- references. A future checker model must condition relocation on the current
-- facts of the opaque storage. Until then, callers must conservatively ensure
-- that no live opaque value depends on storage invalidated by this move.
trusted_opaque_relocate_owned#(.t: Type)(.source: $&t, .destination: $&t) -> () := {
}

trusted_opaque_drop_owned#(.t: Type)(.slot: $&t) -> () := {
    deinit(.self = slot)
}

-- Use this overload when the element destructor may reach an allocator. The
-- explicit input keeps the monomorphized trusted function self-contained.
trusted_opaque_drop_owned#(.t: Type)(.slot: $&t, .allocator: $&Allocator) -> () := {
    deinit(.self = slot)
}
