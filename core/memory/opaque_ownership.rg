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
-- Dependencies are conservative and monotonic for that domain, including
-- dependencies introduced later by mutation through an opaque slot pointer.
-- Pointer provenance retains the concrete storage generation observed when
-- the pointer was created; refreshing the domain never rebinds old aliases.
trusted_opaque_store_owned_in#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .destination: $&t, .source: t) -> () := {
    destination& = source
}

-- Extracts one live opaque-owned representation into precise ownership. The
-- slot becomes empty and the returned value becomes responsible for cleanup.
-- `storage` identifies the conservative domain; it has no runtime role. The
-- caller guarantees that `slot` contains exactly one live value.
trusted_opaque_take_owned_in#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .slot: $&t) -> (.result: t) := {
    result = slot&
}

-- Moves one live opaque-owned representation between slots. It neither
-- destroys the source representation nor creates precise ownership for the
-- destination. The caller must ensure that `source` is live, `destination`
-- is empty, and the two slots are distinct.
--
-- Passing store_owned once is not a permanent relocatability proof. Relocation
-- is rejected when current aggregate facts show that later mutation introduced
-- a dependency on the source opaque domain's storage generation.
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

-- The caller guarantees every opaque runtime value in `storage` was already
-- destroyed. This discharges only the checker's domain-level hidden temporal
-- dependencies; it does not free storage or refresh its generation.
trusted_opaque_release_all#(.t: Type)(.storage: $&t) -> () := {
}
