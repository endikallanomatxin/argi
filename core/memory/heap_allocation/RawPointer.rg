RawPointer#(.t: Type) : Type = (
    .address: UIntNative
)

RawPointer#(.t: Type) implements ImplicitlyCopyable

raw_pointer#(.t: Type)(.address: UIntNative) -> (.raw: RawPointer#(.t: t)) := {
    raw = (.address = address)
}

erase_reference#(.t: Type)(.base: &t) -> (.reference: &Any) := {
    reference = reinterpret_reference#(.from: t, .to: Any)(.base = base).reference
}

erase_mutable_reference#(.t: Type)(.base: $&t) -> (.reference: &Any) := {
    readonly ::= read_reference#(.t: t)(.base = base).reference
    reference = reinterpret_reference#(.from: t, .to: Any)(.base = readonly).reference
}

-- The caller must ensure that raw addresses a live, aligned t whose lifetime
-- is bounded by root. This operation borrows root; it does not create one.
establish_inherited_reference#(.t: Type)(
    .raw: RawPointer#(.t: t),
    .root: &Any,
) -> (.reference: $&t) := {
    reference = __trusted_reference_from_address#(.to: $&t)(.address = raw.address)
}

-- Incorporates newly acquired physical storage into an existing temporal
-- domain. Unlike ordinary raw alias establishment, this consumes the unique
-- StorageCapability carried by the physical address.
establish_inherited_storage(
    .address: UIntNative,
    .root: &Any,
) -> (.raw: RawPointer#(.t: UInt8)) := {
    raw = raw_pointer#(.t: UInt8)(.address = address).raw
}

reference_offset#(.t: Type)(
    .base: &t,
    .elements: UIntNative,
) -> (.reference: &t) := {
    address ::= UIntNative(.value = base) + elements * size_of(.type = t)
    reference = __trusted_reference_from_address#(.to: &t)(.address = address)
}

reinterpret_reference#(.from: Type, .to: Type)(
    .base: &from,
) -> (.reference: &to) := {
    reference = __trusted_reference_from_address#(.to: &to)(.address = UIntNative(.value = base))
}

read_reference#(.t: Type)(.base: $&t) -> (.reference: &t) := {
    reference = __trusted_reference_from_address#(.to: &t)(.address = UIntNative(.value = base))
}

mutable_reinterpret_reference#(.from: Type, .to: Type)(
    .base: $&from,
) -> (.reference: $&to) := {
    reference = __trusted_reference_from_address#(.to: $&to)(.address = UIntNative(.value = base))
}

mutable_reference_offset#(.t: Type)(
    .base: $&t,
    .elements: UIntNative,
) -> (.reference: $&t) := {
    address ::= UIntNative(.value = base) + elements * size_of(.type = t)
    reference = __trusted_reference_from_address#(.to: $&t)(.address = address)
}
