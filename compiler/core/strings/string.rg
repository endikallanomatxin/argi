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

CString : Type = (
    .data : UIntNative
)

init (
    .p: $&String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .length: UIntNative,
) -> () := {
    allocation_size ::= length + 1
    data ::= allocate(.self = allocator, .size = allocation_size)
    p& = (
        .allocation = (
            .data = data,
            .size = allocation_size,
        ),
        .length = length,
    )
    bytes_set(.string = p, .index = length, .value = 0)
}

deinit (
    .allocator: $&Allocator = #reach allocator, system.allocator,
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
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: String,
) -> (.out: String) := {
    allocation_size ::= self.length + 1
    new_data ::= allocate(.self = allocator, .size = allocation_size)
    out = (
        .allocation = (
            .data = new_data,
            .size = allocation_size,
        ),
        .length = self.length,
    )

    if allocation_size > 0 {
        src_addr :: UIntNative = cast#(.to: UIntNative)(.value = self.allocation.data)
        dst_addr :: UIntNative = cast#(.to: UIntNative)(.value = out.allocation.data)

        memcpy(
            .dst = cast#(.to: $&Any)(.value = dst_addr),
            .src = cast#(.to: &Any)(.value = src_addr),
            .n = allocation_size,
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

as_view(
    .self: &String,
) -> (.view: StringView) := {
    view = (
        .data = cast#(.to: UIntNative)(.value = self&.allocation.data),
        .length = self&.length,
    )
}

as_c_string(
    .self: &String,
) -> (.text: CString) := {
    text = (
        .data = cast#(.to: UIntNative)(.value = self&.allocation.data)
    )
}

pointer(
    .self: &CString,
) -> (.out: &Char) := {
    out = cast#(.to: &Char)(.value = self&.data)
}
