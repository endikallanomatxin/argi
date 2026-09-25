-- Adds the storage generation of `on` to an existing safe reference.
-- This is a compiler-recognized pure temporal restriction: it neither creates
-- a root nor transfers ownership or storage capability.
restrict_reference#(.t: Type)(
    .input: t,
    .on: &Any,
) -> (.reference: t) := {
    reference = input
}

-- Attach a validity dependency to a value whose use relies on storage that
-- Safety cannot discover from its representation. Ownership is unchanged.
depend_on#(.t: Type)(
    .value: t,
    .on: &Any,
) -> (.result: t) := {
    result = value
}
