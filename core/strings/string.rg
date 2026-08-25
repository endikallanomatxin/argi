String : Type = (
    --
    -- Owning string storage.
    --
    -- `String` should be the standard-library owner for heap-backed text
    -- data, built on top of `Allocation`.
    --
    -- This is also the canonical growable text buffer in core. There is no
    -- separate `TextBuffer` abstraction in the current 0.1 library surface.
    --
    -- Non-owning string slices/views should remain separate borrowed
    -- descriptors.
    --
    .allocation : Allocation
    .length     : UIntNative
)

string_with_length(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .length: UIntNative,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    allocation_size ::= length + 1
    allocate_result ::= allocate_fallible(.self = allocator, .size = allocation_size)
    match allocate_result {
        ..ok payload {
            out :: String = (
                .allocation = (
                    .data = cast#(.to: $&UInt8)(.value = payload),
                    .size = allocation_size,
                ),
                .length = length,
            )
            bytes_set(.string = $&out, .index = length, .value = 0)
            result = ..ok out
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

string_with_capacity(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    allocation_size ::= actual_capacity + 1
    allocate_result ::= allocate_fallible(.self = allocator, .size = allocation_size)
    match allocate_result {
        ..ok payload {
            out :: String = (
                .allocation = (
                    .data = cast#(.to: $&UInt8)(.value = payload),
                    .size = allocation_size,
                ),
                .length = 0,
            )
            bytes_set(.string = $&out, .index = 0, .value = 0)
            result = ..ok out
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

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
        dst_view ::= array_view#(.t: UInt8)(
            .data = out.allocation.data,
            .length = allocation_size,
        )
        src_view ::= array_view_ro#(.t: UInt8)(
            .data = read_reference#(.t: UInt8)(.base = self.allocation.data).reference,
            .length = allocation_size,
        )
        memcpy_bytes(.dst = dst_view, .src = src_view)
    }
}

string_byte_reference (
    .string: &String,
    .index: UIntNative,
) -> (.reference: &UInt8) := {
    reference = reference_offset#(.t: UInt8)(.base = string&.allocation.data, .elements = index)
}

bytes_get (
    .string: &String,
    .index: UIntNative,
) -> (.byte: UInt8) := {
    byte = string_byte_reference(.string = string, .index = index).reference&
}

bytes_set (
    .string: $&String,
    .index: UIntNative,
    .value: UInt8,
) -> () := {
    ptr ::= mutable_reference_offset#(.t: UInt8)(.base = string&.allocation.data, .elements = index).reference
    ptr& = value
}

as_view(
    .self: &String,
) -> (.view: StringView) := {
    view = (
        .data = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference,
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
        dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = self&.length)
        src_view ::= array_view_ro#(.t: UInt8)(.data = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference, .length = self&.length)
        memcpy_bytes(.dst = dst_view, .src = src_view)
    }

    nul_ptr ::= mutable_reference_offset#(.t: UInt8)(.base = new_data, .elements = self&.length).reference
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
    .target_capacity: UIntNative,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    current_capacity ::= capacity(.self = self).value
    if current_capacity >= target_capacity {
        result = ..ok Void()
        return
    }

    new_allocation_size ::= target_capacity + 1
    allocate_result ::= allocate_fallible(.self = allocator, .size = new_allocation_size)
    match allocate_result {
        ..ok payload {
            new_data : $&UInt8 = cast#(.to: $&UInt8)(.value = payload)

            if self&.length > 0 {
                dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = self&.length)
                src_view ::= array_view_ro#(.t: UInt8)(.data = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference, .length = self&.length)
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            nul_ptr ::= mutable_reference_offset#(.t: UInt8)(.base = new_data, .elements = self&.length).reference
            nul_ptr& = 0

            deallocate(.self = allocator, .data = self&.allocation.data, .size = self&.allocation.size)
            self& = (
                .allocation = (
                    .data = new_data,
                    .size = new_allocation_size,
                ),
                .length = self&.length,
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
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
    .source: ArrayViewRO#(.t: UInt8),
) -> () := {
    if source.length > 0 {
        dest_data ::= mutable_reference_offset#(.t: UInt8)(.base = self&.allocation.data, .elements = self&.length).reference
        dest_view ::= array_view#(.t: UInt8)(.data = dest_data, .length = source.length)
        memcpy_bytes(.dst = dest_view, .src = source)
    }

    self& = (
        .allocation = self&.allocation,
        .length = self&.length + source.length,
    )
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

push_byte(
    .self: $&String,
    .byte: UInt8,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if has_space(.self = self).ok {
    } else {
        next_capacity ::= string_growth_capacity(.self = self, .min_capacity = self&.length + 1).value
        growth_result ::= ensure_capacity_growing(.self = self, .target_capacity = next_capacity, .allocator = allocator)
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    string_append_byte(.self = self, .byte = byte)
    result = ..ok Void()
}

push_c_string(
    .self: $&String,
    .text: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    append_length ::= c_string_length(.text = text).length
    target_capacity ::= self&.length + append_length
    growth_result ::= ensure_capacity_growing(.self = self, .target_capacity = target_capacity, .allocator = allocator)
    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= array_view_ro#(.t: UInt8)(
        .data = reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference,
        .length = append_length,
    )
    string_append_bytes(.self = self, .source = source_view)
    result = ..ok Void()
}

push_view(
    .self: $&String,
    .view: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    target_capacity ::= self&.length + view.length
    growth_result ::= ensure_capacity_growing(.self = self, .target_capacity = target_capacity, .allocator = allocator)
    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= array_view_ro#(.t: UInt8)(
        .data = view.data,
        .length = view.length,
    )
    string_append_bytes(.self = self, .source = source_view)
    result = ..ok Void()
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
        .data = reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference,
        .length = c_string_length(.text = text).length,
    )
}

concat_views(
    .left: &StringView,
    .right: &StringView,
) -> (.out: String) := {
    allocator : $&Allocator = #reach allocator, system.allocator
    temp :: String = String(.allocator = allocator, .capacity = left&.length + right&.length)
    left_view ::= array_view_ro#(.t: UInt8)(.data = left&.data, .length = left&.length)
    right_view ::= array_view_ro#(.t: UInt8)(.data = right&.data, .length = right&.length)
    string_append_bytes(.self = $&temp, .source = left_view)
    string_append_bytes(.self = $&temp, .source = right_view)
    out = temp
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
