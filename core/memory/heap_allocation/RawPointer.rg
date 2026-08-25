RawPointer#(.t: Type) : Type = (
    .address: UIntNative
)

raw_pointer#(.t: Type)(.address: UIntNative) -> (.raw: RawPointer#(.t: t)) := {
    raw = (.address = address)
}

establish_fresh_reference#(.t: Type)(
    .raw: RawPointer#(.t: t),
) -> (.reference: $&t) := {
    reference = cast#(.to: $&t)(.value = raw.address)
}

establish_inherited_reference#(.t: Type)(
    .raw: RawPointer#(.t: t),
    .root: $&Any,
) -> (.reference: $&t) := {
    reference = cast#(.to: $&t)(.value = raw.address)
}

reference_offset#(.t: Type)(
    .base: &t,
    .elements: UIntNative,
) -> (.reference: &t) := {
    address ::= cast#(.to: UIntNative)(.value = base) + elements * size_of(.type = t)
    reference = cast#(.to: &t)(.value = address)
}

reinterpret_reference#(.from: Type, .to: Type)(
    .base: &from,
) -> (.reference: &to) := {
    reference = cast#(.to: &to)(.value = cast#(.to: UIntNative)(.value = base))
}

read_reference#(.t: Type)(.base: $&t) -> (.reference: &t) := {
    reference = cast#(.to: &t)(.value = cast#(.to: UIntNative)(.value = base))
}

mutable_reinterpret_reference#(.from: Type, .to: Type)(
    .base: $&from,
) -> (.reference: $&to) := {
    reference = cast#(.to: $&to)(.value = cast#(.to: UIntNative)(.value = base))
}

mutable_reference_offset#(.t: Type)(
    .base: $&t,
    .elements: UIntNative,
) -> (.reference: $&t) := {
    address ::= cast#(.to: UIntNative)(.value = base) + elements * size_of(.type = t)
    reference = cast#(.to: $&t)(.value = address)
}
