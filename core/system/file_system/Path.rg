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

path_is_separator(
        .byte : UInt8,
    ) -> (
        .ok : Bool
    ) := {
    ok = _platform_path_is_separator(.byte = byte).ok
}

path_last_separator_index(
        .view : &StringView,
    ) -> (
        .value : ?UIntNative
    ) := {
    if view&.length == 0 {
        value = ..none
        return
    }

    i :: UIntNative = view&.length

    while i > 0 {
        i = i - 1
        if path_is_separator(.byte = bytes_get(.view = view, .index = i).byte).ok {
            value = ..some(.value = i)
            return
        }
    }

    value = ..none
}

string_view_slice(
        .view   : &StringView,
        .start  : UIntNative,
        .length : UIntNative,
    ) -> (
        .out : StringView
    ) := {
    out = _string_view_subrange(.self = view&, .start = start, .count = length).view
}

Path init(
        .text : String,
    ) -> (
        .result : Path
    ) := {
    result = (
        .text = ~text
    )
}

Path init(
        .view      : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) := {
    constructed :: Path

    assume allocator

    constructed = path_with_view(.view = view, .allocator = allocator)!

    result = ..ok ~constructed
}

path_with_view(
        .view      : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) := {
    assume allocator

    text ::= string_with_capacity(.allocator = allocator, .capacity = view.length)!
    push_view(.self = $&text, .view = view, .allocator = allocator)!

    result = ..ok(.text = ~text)
}

Path deinit(
        .self      : $&Path,
        .allocator : $&Allocator,
    ) -> () := {
    assume allocator

    deinit(.self = $&self&.text, .allocator = allocator)
}

copy(
        .self      : &Path,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) := {
    assume allocator

    text ::= copy(.self = &self&.text, .allocator = allocator)!

    result = ..ok(.text = ~text)
}

as_view(
        .self : &Path,
    ) -> (
        .view : StringView
    ) := {
    view = as_view(&self&.text)
}

as_c_string(
        .self : &Path,
    ) -> (
        .text : &Char
    ) := {
    text = as_c_string(.self = &self&.text)
}

is_absolute(
        .self : &Path,
    ) -> (
        .ok : Bool
    ) := {
    view ::= as_view(self)

    if view.length == 0 {
        ok = false
        return
    }

    ok = _platform_path_root_length(.view = &view).length > 0
}

file_name(
        .self : &Path,
    ) -> (
        .value : ?StringView
    ) := {
    view ::= as_view(self)

    if view.length == 0 {
        value = ..none
        return
    }

    if view.length <= _platform_path_root_length(.view = &view).length {
        value = ..none
        return
    }

    sep_index ::= path_last_separator_index(.view = &view).value

    match sep_index {
        ..some payload {
            start ::= payload.value + 1
            if start >= view.length {
                value = ..none
                return
            }
            value = ..some(
                .value = string_view_slice(
                    .view   = &view
                    .start  = start
                    .length = [
                        view.length
                        - start
                    ]
                )
            )
        }
        ..none {
            value = ..some(.value = view)
        }
    }
}

parent(
        .self : &Path,
    ) -> (
        .value : ?StringView
    ) := {
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

extension(
        .self : &Path,
    ) -> (
        .value : ?StringView
    ) := {
    name ::= file_name(.self = self).value

    match name {
        ..none {
            value = ..none
        }
        ..some payload {
            file_view ::= payload.value
            if file_view.length == 0 {
                value = ..none
                return
            }

            i :: UIntNative = file_view.length
            while i > 0 {
                i = i - 1
                current ::= bytes_get(.view = &file_view, .index = i).byte
                if current == 46 {
                    if i == 0 or i + 1 >= file_view.length {
                        value = ..none
                        return
                    }
                    value = ..some(
                        .value = string_view_slice(
                            .view   = &file_view
                            .start  = i
                            .length = [
                                file_view.length
                                - i
                            ]
                        )
                    )
                    return
                }
            }

            value = ..none
        }
    }
}

join_views(
        .left      : &StringView,
        .right     : &StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) := {
    assume allocator

    native :: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    target_capacity :: UIntNative = 0

    match checked_add(.left = left&.length, .right = right&.length) {
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

    if left&.length > 0 and right&.length > 0 {
        if path_is_separator(.byte = bytes_get(.view = left, .index = left&.length - 1).byte).ok {
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
            left_bytes ::= _trusted_array_view_ro#(.t: UInt8)(
                .data   = left&.data
                .length = left&.length
            )
            string_append_bytes(.self = $&text, .source = left_bytes)

            if left&.length > 0 and right&.length > 0 {
                if path_is_separator(
                    .byte = bytes_get(.view = left, .index = left&.length - 1).byte
                ).ok {
                } else {
                    string_append_byte(.self = $&text, .byte = 47)
                }
            }

            right_bytes ::= _trusted_array_view_ro#(.t: UInt8)(
                .data   = right&.data
                .length = right&.length
            )
            string_append_bytes(.self = $&text, .source = right_bytes)
            result = ..ok(.text = ~text)
            return
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

join(
        .left      : &Path,
        .right     : &Path,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Path, (..out_of_memory))
    ) := {
    assume allocator

    left_view ::= as_view(left)
    right_view ::= as_view(right)

    result = join_views(.left = &left_view, .right = &right_view, .allocator = allocator)
}

operator == (
        .left  : &Path,
        .right : &Path,
    ) -> (
        .ok : Bool
    ) := {
    ok = path_equals(.left = left, .right = right).ok
}

path_equals(
        .left  : &Path,
        .right : &Path,
    ) -> (
        .ok : Bool
    ) := {
    left_view ::= as_view(left)
    right_view ::= as_view(right)
    ok = left_view == right_view
}
