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

string_growth_capacity(
    .self: &String,
    .min_capacity: UIntNative,
) -> (.value: UIntNative) := {
    current_capacity ::= capacity(.self = self).value
    if current_capacity == 0 {
        value = min_capacity
        return
    }

    value = current_capacity * 2
    if value < min_capacity {
        value = min_capacity
    }
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

ensure_capacity_growing(
    .self: $&String,
    .capacity: UIntNative,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    current_capacity ::= capacity(.self = self).value
    if current_capacity >= capacity {
        ok = true
        return
    }

    new_allocation_size ::= capacity + 1
    new_data ::= allocate(.self = allocator, .size = new_allocation_size)
    if cast#(.to: UIntNative)(.value = new_data) == 0 {
        ok = false
        return
    }

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
    ok = true
}

string_append_byte(
    .self: $&String,
    .byte: UInt8,
) -> () := {
    bytes_set(.string = self, .index = self&.length, .value = byte)
    self& = (
        .allocation = self&.allocation,
        .length = self&.length + 1,
    )
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

string_append_bytes(
    .self: $&String,
    .source: UIntNative,
    .length: UIntNative,
) -> () := {
    if length > 0 {
        dest ::= cast#(.to: UIntNative)(.value = self&.allocation.data) + self&.length
        memcpy(
            .dst = cast#(.to: $&Any)(.value = dest),
            .src = cast#(.to: &Any)(.value = source),
            .n = length,
        )
    }

    self& = (
        .allocation = self&.allocation,
        .length = self&.length + length,
    )
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

push_byte(.self: $&String, .byte: UInt8) -> () := {
    if has_space(.self = self).ok {
    } else {
        return
    }

    string_append_byte(.self = self, .byte = byte)
}

push_byte_growing(
    .self: $&String,
    .byte: UInt8,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    if has_space(.self = self).ok {
    } else {
        next_capacity ::= string_growth_capacity(.self = self, .min_capacity = self&.length + 1).value
        if ensure_capacity_growing(.self = self, .capacity = next_capacity, .allocator = allocator).ok {
        } else {
            ok = false
            return
        }
    }

    string_append_byte(.self = self, .byte = byte)
    ok = true
}

push_c_string(
    .self: $&String,
    .text: &Char,
) -> () := {
    available ::= capacity(.self = self).value - self&.length
    append_length ::= c_string_length(.text = text).length
    if append_length > available {
        append_length = available
    }

    string_append_bytes(
        .self = self,
        .source = cast#(.to: UIntNative)(.value = text),
        .length = append_length,
    )
}

push_c_string_growing(
    .self: $&String,
    .text: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    append_length ::= c_string_length(.text = text).length
    target_capacity ::= self&.length + append_length
    if ensure_capacity_growing(.self = self, .capacity = target_capacity, .allocator = allocator).ok {
    } else {
        ok = false
        return
    }

    string_append_bytes(
        .self = self,
        .source = cast#(.to: UIntNative)(.value = text),
        .length = append_length,
    )
    ok = true
}

push_view(
    .self: $&String,
    .view: &StringView,
) -> () := {
    available ::= capacity(.self = self).value - self&.length
    append_length ::= view&.length
    if append_length > available {
        append_length = available
    }

    string_append_bytes(
        .self = self,
        .source = view&.data,
        .length = append_length,
    )
}

push_view_growing(
    .self: $&String,
    .view: &StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.ok: Bool) := {
    target_capacity ::= self&.length + view&.length
    if ensure_capacity_growing(.self = self, .capacity = target_capacity, .allocator = allocator).ok {
    } else {
        ok = false
        return
    }

    string_append_bytes(
        .self = self,
        .source = view&.data,
        .length = view&.length,
    )
    ok = true
}

c_string_length(
    .text: &Char,
) -> (.length: UIntNative) := {
    length = 0
    c_length :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = text) + c_length
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }
        c_length = c_length + 1
    }

    length = c_length
}

c_string_as_view(
    .text: &Char,
) -> (.view: StringView) := {
    view = (
        .data = cast#(.to: UIntNative)(.value = text),
        .length = c_string_length(.text = text).length,
    )
}

concat_views(
    .left: &StringView,
    .right: &StringView,
) -> (.out: String) := {
    allocator : $&Allocator = #reach allocator, system.allocator
    temp :: String = String(.allocator = allocator, .capacity = left&.length + right&.length)
    string_append_bytes(.self = $&temp, .source = left&.data, .length = left&.length)
    string_append_bytes(.self = $&temp, .source = right&.data, .length = right&.length)
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

operator +(
    .left: &String,
    .right: &Char,
) -> (.out: String) := {
    left_view ::= as_view(.self = left)
    right_view ::= c_string_as_view(.text = right)
    out = concat_views(.left = &left_view, .right = &right_view)
}

operator +(
    .left: &String,
    .right: &StringView,
) -> (.out: String) := {
    left_view ::= as_view(.self = left)
    out = concat_views(.left = &left_view, .right = right)
}

operator +(
    .left: &String,
    .right: &String,
) -> (.out: String) := {
    left_view ::= as_view(.self = left)
    right_view ::= as_view(.self = right)
    out = concat_views(.left = &left_view, .right = &right_view)
}

operator +(
    .left: &StringView,
    .right: &Char,
) -> (.out: String) := {
    right_view ::= c_string_as_view(.text = right)
    out = concat_views(.left = left, .right = &right_view)
}

operator +(
    .left: &StringView,
    .right: &StringView,
) -> (.out: String) := {
    out = concat_views(.left = left, .right = right)
}

operator +(
    .left: &StringView,
    .right: &String,
) -> (.out: String) := {
    right_view ::= as_view(.self = right)
    out = concat_views(.left = left, .right = &right_view)
}
