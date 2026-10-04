RawPointer#(.t: Type): Type = (
    .address : UIntNative
)

RawPointer#(.t: Type) implements ImplicitlyCopyable

raw_pointer#(.t: Type)(.address: UIntNative) -> (.raw: RawPointer#(.t: t)) := {
    raw = (.address = address)
}

erase_reference#(.t: Type)(.base: &t) -> (.reference: &Any) := {
    reference = trusted_reinterpret_reference#(.from: t, .to: Any)(.base = base).reference
}

erase_mutable_reference#(.t: Type)(.base: $&t) -> (.reference: &Any) := {
    readonly ::= read_reference#(.t: t)(.base = base).reference
    reference = trusted_reinterpret_reference#(.from: t, .to: Any)(.base = readonly).reference
}

-- The caller must ensure that raw addresses a live, aligned t whose lifetime
-- is bounded by root. This operation borrows root; it does not create one.
trusted_establish_inherited_reference#(
        .t : Type
    )(
        .raw  : RawPointer#(.t: t),
        .root : &Any,
    ) -> (
        .reference : $&t
    ) := {
    reference = __trusted_reference_from_address#(.to: $&t)(.address = raw.address)
}

-- Incorporates newly acquired physical storage into an existing temporal
-- domain. Unlike ordinary raw alias establishment, this consumes the unique
-- StorageCapability carried by the physical address.
trusted_establish_inherited_storage(
        .address : UIntNative,
        .root    : &Any,
    ) -> (
        .raw : RawPointer#(.t: UInt8)
    ) := {
    raw = raw_pointer#(.t: UInt8)(.address = address).raw
}

-- Prevent arithmetic wrap before establishing an offset reference. The caller
-- still proves that the resulting element belongs to the same live region.
_reference_offset_address(
        .address      : UIntNative,
        .elements     : UIntNative,
        .element_size : UIntNative,
    ) -> (
        .result : UIntNative
    ) := {
    offset ::= elements * element_size
    if element_size != 0 and offset / element_size != elements { abort }
    result = address + offset
    if result < address { abort }
}

trusted_reference_offset#(
        .t : Type
    )(
        .base     : &t,
        .elements : UIntNative,
    ) -> (
        .reference : &t
    ) := {
    address ::= _reference_offset_address(
        .address      = UIntNative(.value = base)
        .elements     = elements
        .element_size = size_of(.type = t)
    ).result
    reference = __trusted_reference_from_address#(.to: &t)(.address = address)
}

trusted_reinterpret_reference#(
        .from : Type,
        .to   : Type
    )(
        .base : &from,
    ) -> (
        .reference : &to
    ) := {
    reference = __trusted_reference_from_address#(.to: &to)(.address = UIntNative(.value = base))
}

read_reference#(.t: Type)(.base: $&t) -> (.reference: &t) := {
    reference = __trusted_reference_from_address#(.to: &t)(.address = UIntNative(.value = base))
}

trusted_mutable_reinterpret_reference#(
        .from : Type,
        .to   : Type
    )(
        .base : $&from,
    ) -> (
        .reference : $&to
    ) := {
    reference = __trusted_reference_from_address#(.to: $&to)(.address = UIntNative(.value = base))
}

trusted_mutable_reference_offset#(
        .t : Type
    )(
        .base     : $&t,
        .elements : UIntNative,
    ) -> (
        .reference : $&t
    ) := {
    address ::= _reference_offset_address(
        .address      = UIntNative(.value = base)
        .elements     = elements
        .element_size = size_of(.type = t)
    ).result
    reference = __trusted_reference_from_address#(.to: $&t)(.address = address)
}
