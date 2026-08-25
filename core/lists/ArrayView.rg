ArrayView#(.t: Type) : Type = (
    --
    -- Non-owning view over a contiguous mutable region of elements.
    --
    -- This is a general core descriptor. Interop layers can lower it to the
    -- concrete ABI shape a foreign boundary expects, but the language-level
    -- concept is simply a mutable `pointer + length` view.
    --
    .data   : $&t
    .length : UIntNative
)

ArrayViewRO#(.t: Type) : Type = (
    .data   : &t
    .length : UIntNative
)

array_view_ro#(.t: Type)(.data: &t, .length: UIntNative) -> (.array: ArrayViewRO#(.t: t)) := {
    array = (.data = data, .length = length)
}

array_view#(.t: Type)(
    .data: $&t,
    .length: UIntNative,
) -> (.array: ArrayView#(.t: t)) := {
    array = (
        .data = data,
        .length = length,
    )
}

array_view_from_raw#(.t: Type)(
    .raw: RawPointer#(.t: t),
    .root: $&Any,
    .length: UIntNative,
) -> (.array: ArrayView#(.t: t)) := {
    data ::= establish_inherited_reference#(.t: t)(.raw = raw, .root = root)
    array = array_view#(.t: t)(.data = data, .length = length)
}

array_view_from_address#(.t: Type)(.address: UIntNative, .length: UIntNative) -> (.array: ArrayView#(.t: t)) := {
    array = array_view#(.t: t)(.data = cast#(.to: $&t)(.value = address), .length = length)
}

array_view_element_reference#(.t: Type)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.reference: &t) := {
    reference = reference_offset#(.t: t)(.base = self&.data, .elements = index)
}

operator get[]#(.t: Type)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    value = array_view_element_reference#(.t: t)(.self = self, .index = index).reference&
}

operator set[]#(.t: Type)(
    .self: $&ArrayView#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    ptr ::= mutable_reference_offset#(.t: t)(.base = self&.data, .elements = index)
    ptr& = value
}
