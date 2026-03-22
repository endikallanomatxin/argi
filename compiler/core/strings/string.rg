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
    .allocator: $&Allocator = #reach allocator,
    .length: UIntNative,
) -> () := {
    data ::= allocate(.self = allocator, .size = length)
    p& = (
        .allocation = (
            .data = data,
            .size = length,
        ),
        .length = length,
    )
}

deinit (
    .allocator: $&Allocator = #reach allocator,
    .self: $&String,
) -> () := {
    zero :: UIntNative = 0
    deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
    self& = (
        .allocation = self&.allocation,
        .length = zero,
    )
}

copy (
    .allocator: $&Allocator = #reach allocator,
    .self: String,
) -> (.out: String) := {
    new_data ::= allocate(.self = allocator, .size = self.length)
    out = (
        .allocation = (
            .data = new_data,
            .size = self.length,
        ),
        .length = self.length,
    )

    if self.length > 0 {
        src_addr :: UIntNative = cast#(.to: UIntNative)(.value = self.allocation.data)
        dst_addr :: UIntNative = cast#(.to: UIntNative)(.value = out.allocation.data)

        memcpy(
            .dst = cast#(.to: $&Any)(.value = dst_addr),
            .src = cast#(.to: &Any)(.value = src_addr),
            .n = self.length,
        )
    }
}

string_byte_address (
    .string: &String,
    .index: UIntNative,
) -> (.address: UIntNative) := {
    base :: UIntNative = cast#(.to: UIntNative)(.value = string&.allocation.data)
    address = base + index
}

bytes_get (
    .string: &String,
    .index: UIntNative,
) -> (.byte: UInt8) := {
    addr :: UIntNative = string_byte_address(.string = string, .index = index).address
    ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
    byte = ptr&
}

bytes_set (
    .string: $&String,
    .index: UIntNative,
    .value: UInt8,
) -> () := {
    addr :: UIntNative = string_byte_address(.string = string, .index = index).address
    ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = addr)
    ptr& = value
}
