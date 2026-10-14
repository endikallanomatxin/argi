-- Reserve one byte for String's trailing NUL without assuming a native width.
_string_max_result_length() -> (.length: UIntNative) := {
    length = 0
    bytes ::= size_of(.type = UIntNative)
    index :: UIntNative = 0

    while index < bytes {
        length = length * 256 + 255
        index = index + 1
    }

    length = length - 1
}

String: Type = (
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
        .allocator : $&Allocator,
        .length    : UIntNative,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    if length > _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    allocation_size ::= length + 1
    allocation ::= allocate_bytes(allocator, .size = allocation_size)!
    out :: String = (.allocation = ~allocation, .length = length)
    i :: UIntNative = 0

    while i < length {
        bytes_set(.string = $&out, .index = i, .value = 0)
        i = i + 1
    }

    bytes_set(.string = $&out, .index = length, .value = 0)

    result = ..ok ~out
}

string_with_capacity(
        .allocator : $&Allocator,
        .capacity  : UIntNative,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    actual_capacity ::= capacity
    one :: UIntNative = 1

    if actual_capacity == 0 {
        actual_capacity = one
    }

    if actual_capacity > _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    allocation_size ::= actual_capacity + 1
    allocation ::= allocate_bytes(allocator, .size = allocation_size)!
    out :: String = (.allocation = ~allocation, .length = 0)
    bytes_set(.string = $&out, .index = 0, .value = 0)

    result = ..ok ~out
}

implement#(.A: Type: Allocator) Init#(String, (.allocator: $&A = reach allocator, .length: UIntNative = 0)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .init = (.args: (.allocator: $&A, .length: UIntNative)) -> (.result: Result) {
        result = string_with_length(.allocator = args.allocator, .length = args.length)
    }
)

implement Deinit#(String) (
    .deinit = (.self: $&String) -> () {
        deinit(.self = $&self&.allocation)
    }
)

implement#(.Provider: Type: Allocator) FalliblyCopyable#(String, Provider) (
    .reasons: Type = (..out_of_memory)
    .copy = (
            .self      : &String,
            .allocator : $&Provider,
        ) -> (
            .result : Errable#(String, (..out_of_memory))
        ) {
        assume allocator

        if self&.length > _string_max_result_length().length {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        allocation_size ::= self&.length + 1
        allocation ::= allocate_bytes(allocator, .size = allocation_size)!
        out :: String = (.allocation = ~allocation, .length = self&.length)

        if allocation_size > 0 {
            dst_view ::= _trusted_array_view#(.t: UInt8)(
                .data   = _trusted_allocation_byte_rw(.allocation = $&out.allocation, .offset = 0).reference
                .length = allocation_size
            )
            src_view ::= _trusted_array_view_ro#(.t: UInt8)(
                .data   = _trusted_allocation_byte_ro(.allocation = &self&.allocation, .offset = 0).reference
                .length = allocation_size
            )
            memcpy_bytes(.dst = dst_view, .src = src_view)
        }

        result = ..ok ~out
    }

)

string_byte_reference(
        .string : &String,
        .index  : UIntNative,
    ) -> (
        .reference : &UInt8
    ) := {
    -- The trailing NUL is initialized and intentionally readable.
    if index > string&.length { abort }
    reference = _trusted_allocation_byte_ro(.allocation = &string&.allocation, .offset = index).reference
}

_string_get_byte(
        .view   : &String,
        .index  : UIntNative,
    ) -> (
        .byte : UInt8
    ) := {
    byte = string_byte_reference(.string = view, .index = index).reference&
}

bytes_set(
        .string : $&String,
        .index  : UIntNative,
        .value  : UInt8,
    ) -> () := {
    -- Writers also initialize capacity bytes and the trailing NUL.
    if index >= string&.allocation.size { abort }
    ptr ::= _trusted_allocation_byte_rw(.allocation = $&string&.allocation, .offset = index).reference
    ptr&= value
}

_string_text_view(
        .self : &String,
    ) -> (
        .view : StringView
    ) := {
    view = (
        .data   = _trusted_allocation_byte_ro(.allocation = &self&.allocation, .offset = 0).reference
        .length = self&.length
    )
}

capacity(
        .self : &String,
    ) -> (
        .value : UIntNative
    ) := {
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
    ok = self&.length < capacity(self).value
}

string_growth_capacity(
        .self         : &String,
        .min_capacity : UIntNative,
    ) -> (
        .value : UIntNative
    ) := {
    limit ::= _string_max_result_length().length

    if min_capacity > limit { abort }
    current_capacity ::= capacity(self).value

    if current_capacity == 0 {
        value = min_capacity
        return
    }

    -- Saturate at the largest capacity with room for a trailing NUL.
    if current_capacity > limit / 2 {
        value = limit
    } else {
        value = current_capacity * 2
    }

    if value < min_capacity {
        value = min_capacity
    }
}

ensure_capacity(
        .self      : $&String,
        .capacity  : UIntNative,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    result = ensure_capacity_growing(
        self
        .target_capacity = capacity
        .allocator       = allocator
    )
}

ensure_capacity_growing(
        .self            : $&String,
        .target_capacity : UIntNative,
        .allocator       : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    if target_capacity > _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    current_capacity ::= capacity(self).value

    if current_capacity >= target_capacity {
        result = ..ok Void()
        return
    }

    new_allocation_size ::= target_capacity + 1
    allocate_result ::= allocate_bytes(allocator, .size = new_allocation_size)

    match allocate_result {
        ..ok ~payload {
            new_allocation ::= ~payload
            new_data ::= _trusted_allocation_byte_rw(.allocation = $&new_allocation, .offset = 0).reference

            if self&.length > 0 {
                dst_view ::= _trusted_array_view#(.t: UInt8)(
                    .data   = new_data
                    .length = self&.length
                )
                src_view ::= _trusted_array_view_ro#(.t: UInt8)(
                    .data = _trusted_allocation_byte_ro(
                        .allocation = &self&.allocation
                        .offset     = 0
                    ).reference
                    .length = self&.length
                )
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            nul_ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                .base     = new_data
                .elements = self&.length
            ).reference
            nul_ptr&= 0

            deinit(.self = $&self&.allocation)
            self&= (
                .allocation = ~new_allocation
                .length     = self&.length
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

string_append_byte(
        .self : $&String,
        .byte : UInt8,
    ) -> () := {
    if has_space(self).ok == false { abort }
    bytes_set(.string = self, .index = self&.length, .value = byte)
    self&.length = self&.length + 1
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

string_append_bytes(
        .self   : $&String,
        .source : ArrayViewRO#(.t: UInt8),
    ) -> () := {
    current_capacity ::= capacity(self).value

    if self&.length > current_capacity { abort }
    count ::= length(&source).count

    if count > current_capacity - self&.length { abort }
    if count > 0 {
        dest_data ::= _trusted_allocation_byte_rw(
            .allocation = $&self&.allocation
            .offset     = self&.length
        ).reference
        dest_view ::= _trusted_array_view#(.t: UInt8)(
            .data   = dest_data
            .length = length(&source).count
        )
        memcpy_bytes(.dst = dest_view, .src = source)
    }

    self&.length = self&.length + length(&source).count
    bytes_set(.string = self, .index = self&.length, .value = 0)
}

push_byte(
        .self      : $&String,
        .byte      : UInt8,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    if self&.length >= _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if has_space(self).ok {
    } else {
        next_capacity ::= string_growth_capacity(self, .min_capacity = self&.length + 1).value
        growth_result ::= ensure_capacity_growing(
            self
            .target_capacity = next_capacity
            .allocator       = allocator
        )
        match growth_result {
            ..ok _ {
            }
            ..error _ {
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }

    string_append_byte(self, .byte = byte)

    result = ..ok Void()
}

push_c_string(
        .self      : $&String,
        .text      : &Char,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    append_length ::= c_string_length(.text = text).length
    limit ::= _string_max_result_length().length

    if self&.length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if append_length > limit - self&.length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    target_capacity ::= self&.length + append_length
    growth_result ::= ensure_capacity_growing(
        self
        .target_capacity = target_capacity
        .allocator       = allocator
    )

    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= _trusted_array_view_ro#(.t: UInt8)(
        .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference
        .length = append_length
    )
    string_append_bytes(self, .source = source_view)

    result = ..ok Void()
}

push_view(
        .self      : $&String,
        .view      : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    limit ::= _string_max_result_length().length

    if self&.length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if view.length > limit - self&.length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    target_capacity ::= self&.length + view.length
    growth_result ::= ensure_capacity_growing(
        self
        .target_capacity = target_capacity
        .allocator       = allocator
    )

    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= _trusted_array_view_ro#(.t: UInt8)(
        .data   = view.data
        .length = view.length
    )
    string_append_bytes(self, .source = source_view)

    result = ..ok Void()
}

c_string_length(
        .text : &Char,
    ) -> (
        .length : UIntNative
    ) := {
    length = 0
    c_length :: UIntNative = 0

    while 1 == 1 {
        bytes ::= trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference
        ptr ::= trusted_reference_offset#(.t: UInt8)(.base = bytes, .elements = c_length).reference
        if ptr&== 0 {
            break
        }
        c_length = c_length + 1
    }

    length = c_length
}

c_string_as_view(
        .text : &Char,
    ) -> (
        .view : StringView
    ) := {
    view = (
        .data   = trusted_reinterpret_reference#(.from: Char, .to: UInt8)(.base = text).reference
        .length = c_string_length(.text = text).length
    )
}

concat_views(
        .left      : &StringView,
        .right     : &StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    limit ::= _string_max_result_length().length

    if left&.length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if right&.length > limit - left&.length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    created ::= string_with_capacity(
        .allocator = allocator
        .capacity  = [
            left&.length
            + right&.length
        ]
    )

    match created {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~payload {
            temp ::= ~payload
            left_view ::= _trusted_array_view_ro#(.t: UInt8)(
                .data   = left&.data
                .length = left&.length
            )
            right_view ::= _trusted_array_view_ro#(.t: UInt8)(
                .data   = right&.data
                .length = right&.length
            )
            string_append_bytes($&temp, .source = left_view)
            string_append_bytes($&temp, .source = right_view)
            result = ..ok ~temp
        }
    }
}

implement#(.Provider: Type: Allocator) Add#(String, Char, (
    .left: &String
    .right: &Char
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &String, .right: &Char, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= as_view(args.left)
        right_view ::= c_string_as_view(.text = args.right)

        result = concat_views(.left = &left_view, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Add#(String, StringView, (
    .left: &String
    .right: &StringView
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &String, .right: &StringView, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= as_view(args.left)

        result = concat_views(.left = &left_view, .right = args.right)
    }
)

implement#(.Provider: Type: Allocator) Add#(String, String, (
    .left: &String
    .right: &String
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &String, .right: &String, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= as_view(args.left)
        right_view ::= as_view(args.right)

        result = concat_views(.left = &left_view, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Add#(StringView, Char, (
    .left: &StringView
    .right: &Char
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &StringView, .right: &Char, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        right_view ::= c_string_as_view(.text = args.right)

        result = concat_views(.left = args.left, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Add#(StringView, StringView, (
    .left: &StringView
    .right: &StringView
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &StringView, .right: &StringView, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        result = concat_views(.left = args.left, .right = args.right)
    }
)



implement#(.Provider: Type: Allocator) Add#(StringView, String, (
    .left: &StringView
    .right: &String
    .allocator: $&Provider = reach allocator
)) (
    .Result: Type = Errable#(String, (..out_of_memory))
    .add = (.args: (.left: &StringView, .right: &String, .allocator: $&Provider = reach allocator)) -> (.result: Result) {
        assume allocator ::= args.allocator

        right_view ::= as_view(args.right)

        result = concat_views(.left = args.left, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Concatenation#(StringView, &String, Provider) (
    .join = (.left: StringView, .right: &String, .allocator: $&Provider) -> (.result: Errable#(String, (..out_of_memory))) {
    assume allocator
    right_view := as_view(right)

    result = concat_views(&left, &right_view)
}
)

implement#(.Provider: Type: Allocator) Concatenation#(StringView, StringView, Provider) (
    .join = (.left: StringView, .right: StringView, .allocator: $&Provider) -> (.result: Errable#(String, (..out_of_memory))) {
    assume allocator

    result = concat_views(&left, &right)
}
)

implement#(.Provider: Type: Allocator) Concatenation#(&String, StringView, Provider) (
    .join = (.left: &String, .right: StringView, .allocator: $&Provider) -> (.result: Errable#(String, (..out_of_memory))) {
    assume allocator
    left_view := as_view(left)

    result = concat_views(&left_view, &right)
}
)

implement#(.Provider: Type: Allocator) Concatenation#(&String, &String, Provider) (
    .join = (.left: &String, .right: &String, .allocator: $&Provider) -> (.result: Errable#(String, (..out_of_memory))) {
    assume allocator
    left_view := as_view(left)
    right_view := as_view(right)

    result = concat_views(&left_view, &right_view)
}
)
