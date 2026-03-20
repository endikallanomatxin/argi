String : Type = (
    --
    -- Owning string storage.
    --
    -- `String` should be the standard-library owner for heap-backed text
    -- data, built on top of `Allocation`.
    --
    -- Non-owning string slices/views should remain separate borrowed
    -- descriptors.
    --
    .allocation : Allocation
    .length     : UIntNative
)

init (
    .p: $&String,
    .length: UIntNative,
) -> () := {
    p& = (
        .allocation = allocation_init(.size = length),
        .length = length,
    )
}

deinit (.self: $&String) -> () := {
    zero :: UIntNative = 0
    allocation_deinit(.allocation = self&.allocation)
    self& = (
        .allocation = self&.allocation,
        .length = zero,
    )
}

string_byte_address (
    .string: &String,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = string&.allocation.data)
    address = base + index
}

operator get[] (
    .self: &String,
    .index: UIntNative,
) -> (.byte: UInt8) := {
    addr :: UIntNative = string_byte_address(.string = self, .index = index).address
    ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
    byte = ptr&
}

operator set[] (
    .self: $&String,
    .index: UIntNative,
    .value: UInt8,
) -> () := {
    addr :: UIntNative = string_byte_address(.string = self, .index = index).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = value
}
