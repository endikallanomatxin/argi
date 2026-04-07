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

array_view#(.t: Type)(
    .data: $&t,
    .length: UIntNative,
) -> (.array: ArrayView#(.t: t)) := {
    array = (
        .data = data,
        .length = length,
    )
}

array_view_element_address#(.t: Type)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.address: UIntNative) := {
    stride :: UIntNative = size_of(.type = t)
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.data)
    address = base + index * stride
}

operator get[]#(.t: Type)(
    .self: &ArrayView#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    ptr : &t = cast#(.to: &t)(.value = array_view_element_address#(.t: t)(.self = self, .index = index).address)
    value = ptr&
}

operator set[]#(.t: Type)(
    .self: $&ArrayView#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    ptr : $&t = cast#(.to: $&t)(.value = array_view_element_address#(.t: t)(.self = self, .index = index).address)
    ptr& = value
}
