ArrayView#(.t: Type) : Type = (
    --
    -- Non-owning view over a contiguous mutable region of elements.
    --
    -- This is a general language/core building block, not a C-specific type.
    -- Interop layers can adapt this shape at the boundary when a foreign API
    -- needs a `pointer + length` pair.
    --
    .data   : $&t
    .length : UIntNative
)

init#(.t: Type)(
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
