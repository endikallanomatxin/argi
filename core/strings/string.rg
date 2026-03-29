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

init (
    .p: $&String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> () := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    allocation_size ::= actual_capacity + 1
    data ::= allocate(.self = allocator, .size = allocation_size)
    p& = (
        .allocation = (
            .data = data,
            .size = allocation_size,
        ),
        .length = 0,
    )
    bytes_set(.string = p, .index = 0, .value = 0)
}

deinit (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&String,
) -> () := {
    zero :: UIntNative = 0
    deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
    self& = (
        .allocation = (
            .data = self&.allocation.data,
            .size = self&.allocation.size,
        ),
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

capacity(
    .self: &String,
) -> (.value: UIntNative) := {
    if self&.allocation.size == 0 {
        value = 0
        return
    }

    value = self&.allocation.size - 1
}

clear(.self: $&String) -> () := {
    self& = (
        .allocation = self&.allocation,
        .length = 0,
    )
    if self&.allocation.size > 0 {
        bytes_set(.string = self, .index = 0, .value = 0)
    }
}

has_space(.self: &String) -> (.ok: Bool) := {
    ok = self&.length < capacity(.self = self).value
}

ensure_capacity(
    .self: $&String,
    .capacity: UIntNative,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    current_capacity ::= capacity(.self = self).value
    if current_capacity >= capacity {
        return
    }

    new_allocation_size ::= capacity + 1
    new_data ::= allocate(.self = allocator, .size = new_allocation_size)

    if self&.length > 0 {
        memcpy(
            .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = new_data)),
            .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = self&.allocation.data)),
            .n = self&.length,
        )
    }

    nul_ptr : $&UInt8 = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = new_data) + self&.length)
    nul_ptr& = 0

    deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
    self& = (
        .allocation = (
            .data = new_data,
            .size = new_allocation_size,
        ),
        .length = self&.length,
    )
}

push_byte(.self: $&String, .byte: UInt8) -> () := {
    if has_space(.self = self).ok {
    } else {
        return
    }

    bytes_set(.string = self, .index = self&.length, .value = byte)
    self& = (
        .allocation = self&.allocation,
        .length = self&.length + 1,
    )
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

push_c_string(
    .self: $&String,
    .text: &Char,
) -> () := {
    i :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = text) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }

        if has_space(.self = self).ok {
        } else {
            break
        }

        push_byte(.self = self, .byte = ptr&)
        i = i + 1
    }
}

push_view(
    .self: $&String,
    .view: &StringView,
) -> () := {
    i :: UIntNative = 0
    while i < view&.length {
        if has_space(.self = self).ok {
        } else {
            break
        }

        push_byte(.self = self, .byte = bytes_get(.view = view, .index = i).byte)
        i = i + 1
    }
}

operator +(
    .left: &String,
    .right: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.out: String) := {
    c_length :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = right) + c_length
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }
        c_length = c_length + 1
    }

    left_view ::= as_view(.self = left)
    right_view : StringView = (
        .data = cast#(.to: UIntNative)(.value = right),
        .length = c_length,
    )

    temp :: String = String(.capacity = left_view.length + right_view.length)
    push_view(.self = $&temp, .view = &left_view)
    push_view(.self = $&temp, .view = &right_view)
    out = temp
}

operator ==(
    .left: &String,
    .right: &String,
) -> (.ok: Bool) := {
    left_view ::= as_view(.self = left)
    right_view ::= as_view(.self = right)
    ok = equals(.left = &left_view, .right = &right_view).ok
}

operator ==(
    .left: &String,
    .right: &StringView,
) -> (.ok: Bool) := {
    left_view ::= as_view(.self = left)
    ok = equals(.left = &left_view, .right = right).ok
}

operator ==(
    .left: &String,
    .right: &Char,
) -> (.ok: Bool) := {
    left_view ::= as_view(.self = left)
    ok = equals(.left = &left_view, .right = right).ok
}

operator !=(
    .left: &String,
    .right: &String,
) -> (.ok: Bool) := {
    if left == right {
        ok = false
    } else {
        ok = true
    }
}

operator !=(
    .left: &String,
    .right: &StringView,
) -> (.ok: Bool) := {
    if left == right {
        ok = false
    } else {
        ok = true
    }
}

operator !=(
    .left: &String,
    .right: &Char,
) -> (.ok: Bool) := {
    if left == right {
        ok = false
    } else {
        ok = true
    }
}
