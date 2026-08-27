-- Adds the storage generation of `lifetime` to an existing safe reference.
-- This is a compiler-recognized pure temporal restriction: it neither creates
-- a root nor transfers ownership or storage authority.
restrict_reference#(.t: Type)(
    .input: t,
    .lifetime: &Any,
) -> (.reference: t) := {
    reference = input
}
