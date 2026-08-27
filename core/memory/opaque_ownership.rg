-- Explicit trusted ownership boundaries usable by any library. The checker
-- still enforces every invariant it can prove; callers maintain runtime-slot
-- initializedness and exactly-once destruction manually.
trusted_opaque_store_owned#(.t: Type)(.destination: $&t, .source: t) -> () := {
    destination& = source
}

trusted_opaque_drop_owned#(.t: Type)(.slot: $&t) -> () := {
    deinit(.self = slot)
}
