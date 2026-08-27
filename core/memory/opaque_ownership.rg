-- Explicit trusted ownership boundaries usable by any library. The checker
-- still enforces every invariant it can prove; callers maintain runtime-slot
-- initializedness and exactly-once destruction manually. In particular,
-- drop_owned requires exactly one live value that has not already been taken
-- or dropped; opaque slots intentionally have no dynamic occupancy tracking.
trusted_opaque_store_owned#(.t: Type)(.destination: $&t, .source: t) -> () := {
    destination& = source
}

trusted_opaque_drop_owned#(.t: Type)(.slot: $&t) -> () := {
    deinit(.self = slot)
}

-- Use this overload when the element destructor may reach an allocator. The
-- explicit input keeps the monomorphized trusted function self-contained.
trusted_opaque_drop_owned#(.t: Type)(.slot: $&t, .allocator: $&Allocator) -> () := {
    deinit(.self = slot)
}
