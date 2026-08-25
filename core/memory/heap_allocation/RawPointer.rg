RawPointer#(.t: Type) : Type = (
    -- Raw addresses carry no safe temporal provenance. They may cross FFI,
    -- allocator, OS and runtime boundaries, but must be established in a
    -- validity root before ordinary Argi code dereferences them.
    .address: UIntNative
)

raw_pointer#(.t: Type)(
    .address: UIntNative,
) -> (.raw: RawPointer#(.t: t)) := {
    raw = (.address = address)
}

establish_fresh_reference#(.t: Type)(
    .raw: RawPointer#(.t: t),
) -> (.reference: $&t) #returns_fresh(reference) #raw_boundary := {
    reference = cast#(.to: $&t)(.value = raw.address)
}

establish_inherited_reference#(.t: Type)(
    .raw: RawPointer#(.t: t),
    .root: $&Any,
) -> (.reference: $&t) #returns_follow(reference, root) #raw_boundary := {
    reference = cast#(.to: $&t)(.value = raw.address)
}
