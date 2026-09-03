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
    allocate_result ::= allocate(.self = allocator, .size = allocation_size)
    match allocate_result {
        ..ok ~ payload {
            out :: String = (
                .allocation = ~payload,
                .length = length,
            )
            bytes_set(.string = $&out, .index = length, .value = 0)
            result = ..ok ~out
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
    allocate_result ::= allocate(.self = allocator, .size = allocation_size)
    match allocate_result {
        ..ok ~ payload {
            out :: String = (
                .allocation = ~payload,
                .length = 0,
            )
            bytes_set(.string = $&out, .index = 0, .value = 0)
            result = ..ok ~out
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
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    allocation_size ::= length + 1
    allocated ::= allocate(.self = allocator, .size = allocation_size)
    match allocated {
        ..ok ~ payload {
            p& = (.allocation = ~payload, .length = length)
            bytes_set(.string = p, .index = length, .value = 0)
            result = ..ok Void()
        }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

init (
    .p: $&String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .capacity: UIntNative,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    allocation_size ::= actual_capacity + 1
    allocated ::= allocate(.self = allocator, .size = allocation_size)
    match allocated {
        ..ok ~ payload {
            p& = (.allocation = ~payload, .length = 0)
            bytes_set(.string = p, .index = 0, .value = 0)
            result = ..ok Void()
        }
        ..error _ { result = ..error(.reason = ..out_of_memory) }
    }
}

deinit (
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&String,
) -> () := {
    deinit(.self = $&self&.allocation)
}

copy (
    .self: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    allocation_size ::= self&.length + 1
    allocated ::= allocate(.self = allocator, .size = allocation_size)
    match allocated {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            out :: String = (.allocation = ~payload, .length = self&.length)

            if allocation_size > 0 {
            dst_view ::= array_view#(.t: UInt8)(
                .data = out.allocation.data,
                .length = allocation_size,
            )
            src_view ::= array_view_ro#(.t: UInt8)(
                .data = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference,
                .length = allocation_size,
            )
            memcpy_bytes(.dst = dst_view, .src = src_view)
        }
            result = ..ok ~out
        }
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
    self&.length = 0
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
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = ensure_capacity_growing(.self = self, .target_capacity = capacity, .allocator = allocator)
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
    allocate_result ::= allocate(.self = allocator, .size = new_allocation_size)
    match allocate_result {
        ..ok ~ payload {
            new_allocation ::= ~payload
            new_data ::= new_allocation.data

            if self&.length > 0 {
                dst_view ::= array_view#(.t: UInt8)(.data = new_data, .length = self&.length)
                src_view ::= array_view_ro#(.t: UInt8)(.data = read_reference#(.t: UInt8)(.base = self&.allocation.data).reference, .length = self&.length)
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            nul_ptr ::= mutable_reference_offset#(.t: UInt8)(.base = new_data, .elements = self&.length).reference
            nul_ptr& = 0

            deinit(.self = $&self&.allocation)
            self& = (
                .allocation = ~new_allocation,
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
    self&.length = self&.length + 1
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

    self&.length = self&.length + source.length
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
        bytes ::= reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference
        ptr ::= reference_offset#(.t: UInt8)(.base = bytes, .elements = c_length).reference
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
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    allocator : $&Allocator = #reach allocator, system.allocator
    created ::= string_with_capacity(.allocator = allocator, .capacity = left&.length + right&.length)
    match created {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            temp ::= ~payload
            left_view ::= array_view_ro#(.t: UInt8)(.data = left&.data, .length = left&.length)
            right_view ::= array_view_ro#(.t: UInt8)(.data = right&.data, .length = right&.length)
            string_append_bytes(.self = $&temp, .source = left_view)
            string_append_bytes(.self = $&temp, .source = right_view)
            result = ..ok ~temp
        }
    }
}

operator +(
    .left: &String,
    .right: &Char,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    left_view ::= as_view(.self = left)
    right_view ::= c_string_as_view(.text = right)
    result = concat_views(.left = &left_view, .right = &right_view)
}

operator +(
    .left: &String,
    .right: &StringView,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    left_view ::= as_view(.self = left)
    result = concat_views(.left = &left_view, .right = right)
}

operator +(
    .left: &String,
    .right: &String,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    left_view ::= as_view(.self = left)
    right_view ::= as_view(.self = right)
    result = concat_views(.left = &left_view, .right = &right_view)
}

operator +(
    .left: &StringView,
    .right: &Char,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    right_view ::= c_string_as_view(.text = right)
    result = concat_views(.left = left, .right = &right_view)
}

operator +(
    .left: &StringView,
    .right: &StringView,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    result = concat_views(.left = left, .right = right)
}

String implements FalliblyCopyable#(.reasons: (..out_of_memory))

operator +(
    .left: &StringView,
    .right: &String,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    right_view ::= as_view(.self = right)
    result = concat_views(.left = left, .right = &right_view)
}
