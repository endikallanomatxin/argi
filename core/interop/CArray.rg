CArray#(.t: Type) : Type = (
    --
    -- Non-owning C-style array view.
    --
    -- This is the baseline shape for interoperating with APIs that expose
    -- `pointer + length` data without transferring ownership.
    --
    .data   : $&t
    .length : UIntNative
)

init#(.t: Type)(
    .data: $&t,
    .length: UIntNative,
) -> (.array: CArray#(.t: t)) := {
    array = (
        .data = data,
        .length = length,
    )
}

c_array_element_address#(.t: Type)(
    .self: &CArray#(.t: t),
    .index: UIntNative,
) -> (.address: UIntNative) := {
    stride :: UIntNative = size_of(.type = t)
    base :: UIntNative = cast#(.to: UIntNative)(.value = self&.data)
    address = base + index * stride
}

operator get[]#(.t: Type)(
    .self: &CArray#(.t: t),
    .index: UIntNative,
) -> (.value: t) := {
    ptr : &t = cast#(.to: &t)(.value = c_array_element_address#(.t: t)(.self = self, .index = index).address)
    value = ptr&
}

operator set[]#(.t: Type)(
    .self: $&CArray#(.t: t),
    .index: UIntNative,
    .value: t,
) -> () := {
    ptr : $&t = cast#(.to: $&t)(.value = c_array_element_address#(.t: t)(.self = self, .index = index).address)
    ptr& = value
}
