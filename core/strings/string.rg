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

_StringShape: Type = (.marker: UInt8)

implement Deinit#(_StringShape) (.deinit = (.self: $&_StringShape) -> () {})

String: Type = (
    -- UTF-8 text with private storage and an initialized trailing NUL.
    ._allocation : Allocation
    ._length     : UIntNative
    ._shape      : _StringShape
)

string_with_length#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .allocator: $&AllocatorType, .length: UIntNative
) -> (.result: Errable#(String, (..out_of_memory))) := {
    assume allocator

    if length > _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    allocation_size ::= length + 1
    allocation ::= allocate_bytes(allocator, .size = allocation_size)!
    out :: String = (._allocation = ~allocation, ._length = length, ._shape = (.marker = 0))
    i :: UIntNative = 0

    while i < length {
        _string_set_byte(.string = $&out, .index = i, .value = 0)
        i = i + 1
    }

    _string_set_byte(.string = $&out, .index = length, .value = 0)

    result = ..ok ~out
}

string_with_capacity#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .allocator: $&AllocatorType, .capacity: UIntNative
) -> (.result: Errable#(String, (..out_of_memory))) := {
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
    out :: String = (._allocation = ~allocation, ._length = 0, ._shape = (.marker = 0))
    _string_set_byte(.string = $&out, .index = 0, .value = 0)

    result = ..ok ~out
}

implement#(.A: Type: Allocator) Init#(
    String, (.allocator: $&A = reach allocator, .length: UIntNative = 0)
) (
    .Result : Type = Errable#(String, (..out_of_memory))
    .init   = (.args: (.allocator: $&A, .length: UIntNative)) -> (.result: Result) {
        result = string_with_length(.allocator = args.allocator, .length = args.length)
    }
)

implement Deinit#(String) (
    .deinit = (.self: $&String) -> () {
        deinit(.self = $&self&._allocation)
    }
)

implement#(.Provider: Type: Allocator) FalliblyCopyable#(String, Provider) (
    .reasons : Type = (..out_of_memory)
    .copy    = (.self: &String, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    ) {
        assume allocator

        if self&._length > _string_max_result_length().length {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        allocation_size ::= self&._length + 1
        allocation ::= allocate_bytes(allocator, .size = allocation_size)!
        out :: String = (
            ._allocation = ~allocation, ._length = self&._length, ._shape = (.marker = 0)
        )

        if allocation_size > 0 {
            dst_view ::= _trusted_mutable_array_view#(.t: UInt8)(
                .data = _trusted_allocation_byte_rw(
                    .allocation = $&out._allocation, .offset = 0
                ).reference
                .length = allocation_size
            )
            src_view ::= _trusted_array_view#(.t: UInt8)(
                .data = _trusted_allocation_byte_ro(
                    .allocation = &self&._allocation, .offset = 0
                ).reference
                .length = allocation_size
            )
            memcpy_bytes(.dst = dst_view, .src = src_view)
        }

        result = ..ok ~out
    }

)

-- The trailing NUL belongs to C interop, outside the logical byte range.
string_byte_reference(.string: &String, .index: UIntNative) -> (
    .result : Errable#(&UInt8, (..out_of_bounds))
) := {
    if index >= string&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    result = ..ok _trusted_allocation_byte_ro(
        .allocation = &string&._allocation, .offset = index
    ).reference
}

_string_get_byte(.view: &String, .index: UIntNative) -> (
    .result : Errable#(UInt8, (..out_of_bounds))
) := {
    reference ::= string_byte_reference(.string = view, .index = index)!
    result = ..ok reference&
}

_string_set_byte(.string: $&String, .index: UIntNative, .value: UInt8) -> () := {
    _invalidate_string(string)
    -- Writers also initialize capacity bytes and the trailing NUL.
    if index >= string&._allocation.size { abort }
    ptr ::= _trusted_allocation_byte_rw(
        .allocation = $&string&._allocation, .offset = index
    ).reference
    ptr&= value
}

_string_text_view(.self: &String) -> (.view: StringView) := {
    if self&._length == 0 {
        view = ""
        return
    }
    first ::= _trusted_allocation_byte_ro(
        .allocation = &self&._allocation, .offset = 0
    ).reference
    borrowed ::= depend_on#(.t: &UInt8)(
        .value = first
        .on    = erase_reference#(.t: _StringShape)(.base = &self&._shape).reference
    ).result
    view = (._data = borrowed, ._length = self&._length)
}

capacity(.self: &String) -> (.value: UIntNative) := {
    if self&._allocation.size == 0 {
        value = 0
        return
    }

    value = self&._allocation.size - 1
}

_invalidate_string(.self: $&String) -> () := {
    shape ::= $&self&._shape
    deinit(.self = shape)
    shape&= (.marker = 0)
}

clear(.self: $&String) -> () := {
    _invalidate_string(self)
    self&._length = 0

    if self&._allocation.size > 0 {
        _string_set_byte(.string = self, .index = 0, .value = 0)
    }
}

has_space(.self: &String) -> (.ok: Bool) := {
    ok = self&._length < capacity(self).value
}

string_growth_capacity(.self: &String, .min_capacity: UIntNative) -> (.value: UIntNative) := {
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

ensure_capacity#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&String, .capacity: UIntNative, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_memory))) := {
    assume allocator

    result = ensure_capacity_growing(self, .target_capacity = capacity, .allocator = allocator)
}

ensure_capacity_growing#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&String, .target_capacity: UIntNative, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_memory))) := {
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
            new_data ::= _trusted_allocation_byte_rw(
                .allocation = $&new_allocation, .offset = 0
            ).reference

            if self&._length > 0 {
                dst_view ::= _trusted_mutable_array_view#(.t: UInt8)(
                    .data = new_data, .length = self&._length
                )
                src_view ::= _trusted_array_view#(.t: UInt8)(
                    .data = _trusted_allocation_byte_ro(
                        .allocation = &self&._allocation, .offset = 0
                    ).reference
                    .length = self&._length
                )
                memcpy_bytes(.dst = dst_view, .src = src_view)
            }

            nul_ptr ::= trusted_mutable_reference_offset#(.t: UInt8)(
                .base = new_data, .elements = self&._length
            ).reference
            nul_ptr&= 0

            deinit(.self = $&self&._allocation)
            self&= (
                ._allocation = ~new_allocation
                ._length     = self&._length
                ._shape      = (.marker = 0)
            )
            result = ..ok Void()
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

_string_append_byte(.self: $&String, .byte: UInt8) -> () := {
    if has_space(self).ok == false { abort }
    _string_set_byte(.string = self, .index = self&._length, .value = byte)
    self&._length = self&._length + 1
    _string_set_byte(.string = self, .index = self&._length, .value = 0)
}

_string_append_bytes(.self: $&String, .source: ArrayView#(.t: UInt8)) -> () := {
    current_capacity ::= capacity(self).value

    if self&._length > current_capacity { abort }
    count ::= length(&source).count

    if count > current_capacity - self&._length { abort }
    if count > 0 {
        dest_data ::= _trusted_allocation_byte_rw(
            .allocation = $&self&._allocation, .offset = self&._length
        ).reference
        dest_view ::= _trusted_mutable_array_view#(.t: UInt8)(
            .data = dest_data, .length = length(&source).count
        )
        memcpy_bytes(.dst = dest_view, .src = source)
    }

    self&._length = self&._length + length(&source).count
    _string_set_byte(.string = self, .index = self&._length, .value = 0)
}

_string_push_byte#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&String, .byte: UInt8, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_memory))) := {
    assume allocator

    if self&._length >= _string_max_result_length().length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if has_space(self).ok {
    } else {
        next_capacity ::= string_growth_capacity(self, .min_capacity = self&._length + 1).value
        growth_result ::= ensure_capacity_growing(
            self, .target_capacity = next_capacity, .allocator = allocator
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

    _string_append_byte(self, .byte = byte)

    result = ..ok Void()
}

push_c_string#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&String, .text: &CChar, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_memory, ..invalid_utf8))) := {
    assume allocator

    append_length ::= c_string_length(.text = text).length
    limit ::= _string_max_result_length().length

    if self&._length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if append_length > limit - self&._length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    target_capacity ::= self&._length + append_length
    growth_result ::= ensure_capacity_growing(
        self, .target_capacity = target_capacity, .allocator = allocator
    )

    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= _trusted_array_view#(.t: UInt8)(
        .data = trusted_reinterpret_reference#(.from: CChar, .to: UInt8)(
            .base = text
        ).reference
        .length = append_length
    )
    -- Capacity reservation may call user code; certify the bytes afterwards.
    _ ::= validate_utf8_bytes(.bytes = source_view)!
    _string_append_bytes(self, .source = source_view)

    result = ..ok Void()
}

push_view#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .self: $&String, .view: StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(Void, (..out_of_memory))) := {
    assume allocator

    limit ::= _string_max_result_length().length

    if self&._length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if view._length > limit - self&._length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    target_capacity ::= self&._length + view._length
    growth_result ::= ensure_capacity_growing(
        self, .target_capacity = target_capacity, .allocator = allocator
    )

    match growth_result {
        ..ok _ {
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    source_view ::= _trusted_array_view#(.t: UInt8)(.data = view._data, .length = view._length)
    _string_append_bytes(self, .source = source_view)

    result = ..ok Void()
}

c_string_length(.text: &CChar) -> (.length: UIntNative) := {
    length = 0
    c_length :: UIntNative = 0

    while 1 == 1 {
        bytes ::= trusted_reinterpret_reference#(.from: CChar, .to: UInt8)(
            .base = text
        ).reference
        ptr ::= trusted_reference_offset#(.t: UInt8)(
            .base = bytes, .elements = c_length
        ).reference
        if ptr&== 0 {
            break
        }
        c_length = c_length + 1
    }

    length = c_length
}

_trusted_c_string_view(.text: &CChar) -> (.view: StringView) := {
    bytes ::= _c_string_bytes(.text = text)
    _ ::= unwrap_or_abort(.value = validate_utf8_bytes(.bytes = bytes))
    if length(&bytes).count == 0 {
        view = ""
        return
    }
    view = (._data = data(&bytes).pointer, ._length = length(&bytes).count)
}

concat_views#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .left: &StringView, .right: &StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(String, (..out_of_memory))) := {
    assume allocator

    limit ::= _string_max_result_length().length

    if left&._length > limit {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if right&._length > limit - left&._length {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    created ::= string_with_capacity(
        .allocator = allocator, .capacity = [left&._length + right&._length]
    )

    match created {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~payload {
            temp ::= ~payload
            left_view ::= _trusted_array_view#(.t: UInt8)(
                .data = left&._data, .length = left&._length
            )
            right_view ::= _trusted_array_view#(.t: UInt8)(
                .data = right&._data, .length = right&._length
            )
            _string_append_bytes($&temp, .source = left_view)
            _string_append_bytes($&temp, .source = right_view)
            result = ..ok ~temp
        }
    }
}

implement#(.Provider: Type: Allocator) Add#(
    String, CChar, (.left: &String, .right: &CChar, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory, ..invalid_utf8))
    .add    = (
        .args : (.left: &String, .right: &CChar, .allocator: $&Provider = reach allocator)
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= view(args.left)
        right_text ::= string_from_c_string(.text = args.right)!
        right_view ::= view(&right_text)

        combined ::= concat_views(.left = &left_view, .right = &right_view)!
        result = ..ok ~combined
    }
)

implement#(.Provider: Type: Allocator) Add#(
    String,
    StringView,
    (.left: &String, .right: &StringView, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory))
    .add    = (
        .args : (.left: &String, .right: &StringView, .allocator: $&Provider = reach allocator)
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= view(args.left)

        result = concat_views(.left = &left_view, .right = args.right)
    }
)

implement#(.Provider: Type: Allocator) Add#(
    String, String, (.left: &String, .right: &String, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory))
    .add    = (
        .args : (.left: &String, .right: &String, .allocator: $&Provider = reach allocator)
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        left_view ::= view(args.left)
        right_view ::= view(args.right)

        result = concat_views(.left = &left_view, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Add#(
    StringView,
    CChar,
    (.left: &StringView, .right: &CChar, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory, ..invalid_utf8))
    .add    = (
        .args : (.left: &StringView, .right: &CChar, .allocator: $&Provider = reach allocator)
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        right_text ::= string_from_c_string(.text = args.right)!
        right_view ::= view(&right_text)

        combined ::= concat_views(.left = args.left, .right = &right_view)!
        result = ..ok ~combined
    }
)

implement#(.Provider: Type: Allocator) Add#(
    StringView,
    StringView,
    (.left: &StringView, .right: &StringView, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory))
    .add    = (
        .args : (
            .left: &StringView, .right: &StringView, .allocator: $&Provider = reach allocator
        )
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        result = concat_views(.left = args.left, .right = args.right)
    }
)

implement#(.Provider: Type: Allocator) Add#(
    StringView,
    String,
    (.left: &StringView, .right: &String, .allocator: $&Provider = reach allocator)
) (
    .Result : Type = Errable#(String, (..out_of_memory))
    .add    = (
        .args : (.left: &StringView, .right: &String, .allocator: $&Provider = reach allocator)
    ) -> (.result: Result) {
        assume allocator ::= args.allocator

        right_view ::= view(args.right)

        result = concat_views(.left = args.left, .right = &right_view)
    }
)

implement#(.Provider: Type: Allocator) Concatenation#(StringView, &String, Provider) (
    .join = (.left: StringView, .right: &String, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    ) {
        assume allocator
        right_view := view(right)

        result = concat_views(&left, &right_view)
    }
)

implement#(.Provider: Type: Allocator) Concatenation#(StringView, StringView, Provider) (
    .join = (.left: StringView, .right: StringView, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    ) {
        assume allocator

        result = concat_views(&left, &right)
    }
)

implement#(.Provider: Type: Allocator) Concatenation#(&String, StringView, Provider) (
    .join = (.left: &String, .right: StringView, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    ) {
        assume allocator
        left_view := view(left)

        result = concat_views(&left_view, &right)
    }
)

implement#(.Provider: Type: Allocator) Concatenation#(&String, &String, Provider) (
    .join = (.left: &String, .right: &String, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    ) {
        assume allocator
        left_view := view(left)
        right_view := view(right)

        result = concat_views(&left_view, &right_view)
    }
)

-- Copy before validation: allocator callbacks may mutate borrowed input bytes.
-- Only the independent, fully validated text escapes this function.
string_from_bytes#(.Provider: Type: Allocator)(
    .bytes: ArrayView#(UInt8), .allocator: $&Provider = reach allocator
) -> (.result: Errable#(String, (..invalid_utf8, ..out_of_memory))) := {
    assume allocator
    size ::= length(&bytes).count
    text ::= string_with_capacity(.allocator = allocator, .capacity = size)!
    _string_append_bytes($&text, .source = bytes)
    _ ::= _validate_string(.self = &text)!
    result = ..ok ~text
}

push_ascii#(.Provider: Type: Allocator)(
    .self: $&String, .byte: UInt8, .allocator: $&Provider = reach allocator
) -> (.result: Errable#(Void, (..out_of_memory))) := {
    assume allocator
    if byte >= 128 { abort }
    _string_push_byte(self, .byte = byte, .allocator = allocator)!
    result = ..ok Void()
}

push_scalar#(.Provider: Type: Allocator)(
    .self: $&String, .scalar: UnicodeScalar, .allocator: $&Provider = reach allocator
) -> (.result: Errable#(Void, (..out_of_memory))) := {
    assume allocator
    encoded ::= zeroed#(.t: [4]UInt8)()
    storage ::= view($&encoded)
    width ::= unwrap_or_abort(.value = utf8_encode(.scalar = scalar, .buffer = storage))
    if width > _string_max_result_length().length - self&._length {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    target ::= self&._length + width
    ensure_capacity_growing(self, .target_capacity = target, .allocator = allocator)!
    prefix ::= unwrap_or_abort(.value = slice(&storage, .start = 0, .count = width))
    _string_append_bytes(self, .source = as_readonly(&prefix).view)
    result = ..ok Void()
}

_validate_string(.self: &String) -> (.result: Errable#(Void, (..invalid_utf8))) := {
    if self&._length == 0 {
        result = ..ok Void()
        return
    }
    bytes ::= _trusted_array_view#(UInt8)(
        .data = _trusted_allocation_byte_ro(
            .allocation = &self&._allocation, .offset = 0
        ).reference
        .length = self&._length
    )
    _ ::= validate_utf8_bytes(.bytes = bytes)!
    result = ..ok Void()
}

set_ascii(.self: $&String, .index: UIntNative, .byte: UInt8) -> (
    .result : Errable#(Void, (..invalid_codepoint, ..out_of_bounds))
) := {
    if index >= self&._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    if [
        byte >= 128
        or unwrap_or_abort(.value = _string_get_byte(.view = self, .index = index)) >= 128
    ] {
        result = ..error(.reason = ..invalid_codepoint)
        return
    }
    _string_set_byte(.string = self, .index = index, .value = byte)
    result = ..ok Void()
}

append_ascii_assume_capacity(.self: $&String, .byte: UInt8) -> () := {
    if byte >= 128 { abort }
    _string_append_byte(self, .byte = byte)
}

append_text_assume_capacity(.self: $&String, .text: StringView) -> () := {
    _string_append_bytes(self, .source = string_bytes(.text = text))
}

implement Equal#(String, String, (.left: &String, .right: &String)) (
    .equal = (.args: (.left: &String, .right: &String)) -> (.ok: Bool) {
        ok = view(args.left) == view(args.right)
    }
)
