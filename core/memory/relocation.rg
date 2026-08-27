-- Moves an existing value representation between structural Places without
-- copying or destroying it. The compiler lowers this primitive directly.
-- References into the source Place are not retargeted; relocation does not
-- provide address stability for self-referential values.
relocate#(.t: Type)(
    .source: $&t,
    .destination: $&t,
) -> () := {
}
