--
-- Baseline owning path type.
--
-- Paths own their UTF-8 text. Separator and drive-root recognition follows
-- the compilation target; joining uses '/' on both supported platform families.
-- This type does not canonicalize paths or query the filesystem.
--
Path: Type = (
    .text : String
)

path_is_separator(.byte: UInt8) -> (.ok: Bool) := {
    ok = _platform_path_is_separator(.byte = byte).ok
}

path_last_separator_index(.view: &StringView) -> (.value: ?UIntNative) := {
    if view&._length == 0 {
        value = ..none
        return
    }

    i :: UIntNative = view&._length

    while i > 0 {
        i = i - 1
        if path_is_separator(
            .byte = unwrap_or_abort(.value = bytes_get(.view = view, .index = i))
        ).ok {
            value = ..some(.value = i)
            return
        }
    }

    value = ..none
}

string_view_slice(.view: &StringView, .start: UIntNative, .length: UIntNative) -> (
    .out : StringView
) := {
    out = _string_view_subrange(view&, .start = start, .count = length).view
}

implement Init#(Path, (.text: String)) (
    .Result : Type = Path
    .init   = (.args: (.text: String)) -> (.result: Result) {
        text ::= ~args.text

        result = (.text = ~text)
    }
)

path_with_view#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .view: StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(Path, (..out_of_memory))) := {
    assume allocator

    text ::= string_with_capacity(.allocator = allocator, .capacity = view._length)!
    push_view($&text, .view = view, .allocator = allocator)!

    result = ..ok(.text = ~text)
}

implement Deinit#(Path) (
    .deinit = (.self: $&Path) -> () {
        deinit(.self = $&self&.text)
    }
)

implement#(.Provider: Type: Allocator) FalliblyCopyable#(Path, Provider) (
    .reasons : Type = (..out_of_memory)
    .copy    = (.self: &Path, .allocator: $&Provider) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) {
        assume allocator

        text ::= copy(&self&.text, .allocator = allocator)!

        result = ..ok(.text = ~text)
    }

)

as_view(.self: &Path) -> (.view: StringView) := {
    view = as_view(&self&.text)
}

as_c_string(.self: &Path) -> (.text: &Char) := {
    text = as_c_string(&self&.text)
}

is_absolute(.self: &Path) -> (.ok: Bool) := {
    view ::= as_view(self)

    if view._length == 0 {
        ok = false
        return
    }

    ok = _platform_path_root_length(.view = &view).length > 0
}

file_name(.self: &Path) -> (.value: ?StringView) := {
    view ::= as_view(self)

    if view._length == 0 {
        value = ..none
        return
    }

    if view._length <= _platform_path_root_length(.view = &view).length {
        value = ..none
        return
    }

    sep_index ::= path_last_separator_index(.view = &view).value

    match sep_index {
        ..some payload {
            start ::= payload.value + 1
            if start >= view._length {
                value = ..none
                return
            }
            value = ..some(
                .value = string_view_slice(
                    .view = &view, .start = start, .length = [view._length - start]
                )
            )
        }
        ..none {
            value = ..some(.value = view)
        }
    }
}

parent(.self: &Path) -> (.value: ?StringView) := {
    view ::= as_view(self)
    sep_index ::= path_last_separator_index(.view = &view).value

    match sep_index {
        ..some payload {
            root_length ::= _platform_path_root_length(.view = &view).length
            if payload.value < root_length {
                value = ..some(
                    .value = string_view_slice(.view = &view, .start = 0, .length = root_length)
                )
                return
            }
            value = ..some(
                .value = string_view_slice(.view = &view, .start = 0, .length = payload.value)
            )
        }
        ..none {
            value = ..none
        }
    }
}

extension(.self: &Path) -> (.value: ?StringView) := {
    name ::= file_name(self).value

    match name {
        ..none {
            value = ..none
        }
        ..some payload {
            file_view ::= payload.value
            if file_view._length == 0 {
                value = ..none
                return
            }

            i :: UIntNative = file_view._length
            while i > 0 {
                i = i - 1
                current ::= unwrap_or_abort(.value = bytes_get(.view = &file_view, .index = i))
                if current == 46 {
                    if i == 0 or i + 1 >= file_view._length {
                        value = ..none
                        return
                    }
                    value = ..some(
                        .value = string_view_slice(
                            .view = &file_view, .start = i, .length = [file_view._length - i]
                        )
                    )
                    return
                }
            }

            value = ..none
        }
    }
}

join_views#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .left: &StringView, .right: &StringView, .allocator: $&AllocatorType
) -> (.result: Errable#(Path, (..out_of_memory))) := {
    assume allocator

    native :: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    target_capacity :: UIntNative = 0

    match checked_add(.left = left&._length, .right = right&._length) {
        ..ok count { target_capacity = count }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }
    -- Strings require a trailing NUL in addition to the visible capacity.
    if target_capacity == maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if left&._length > 0 and right&._length > 0 {
        if path_is_separator(
            .byte = unwrap_or_abort(
                .value = bytes_get(.view = left, .index = left&._length - 1)
            )
        ).ok {
        } else {
            if target_capacity == maximum - 1 {
                result = ..error(.reason = ..out_of_memory)
                return
            }
            target_capacity = target_capacity + 1
        }
    }

    created ::= string_with_capacity(.allocator = allocator, .capacity = target_capacity)

    match created {
        ..ok ~created_text {
            text ::= ~created_text
            left_bytes ::= _trusted_array_view#(.t: UInt8)(
                .data = left&._data, .length = left&._length
            )
            _string_append_bytes($&text, .source = left_bytes)

            if left&._length > 0 and right&._length > 0 {
                if path_is_separator(
                    .byte = unwrap_or_abort(
                        .value = bytes_get(.view = left, .index = [left&._length - 1])
                    )
                ).ok {
                } else {
                    _string_append_byte($&text, .byte = 47)
                }
            }

            right_bytes ::= _trusted_array_view#(.t: UInt8)(
                .data = right&._data, .length = right&._length
            )
            _string_append_bytes($&text, .source = right_bytes)
            result = ..ok(.text = ~text)
            return
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

join#(.AllocatorType: Type: Allocator#(AllocatorType))(
    .left: &Path, .right: &Path, .allocator: $&AllocatorType
) -> (.result: Errable#(Path, (..out_of_memory))) := {
    assume allocator

    left_view ::= as_view(left)
    right_view ::= as_view(right)

    result = join_views(.left = &left_view, .right = &right_view, .allocator = allocator)
}

implement Equal#(Path, Path, (.left: &Path, .right: &Path)) (
    .equal = (.args: (.left: &Path, .right: &Path)) -> (.ok: Bool) {
        ok = path_equals(.left = args.left, .right = args.right).ok
    }
)

path_equals(.left: &Path, .right: &Path) -> (.ok: Bool) := {
    left_view ::= as_view(left)
    right_view ::= as_view(right)
    ok = left_view == right_view
}
