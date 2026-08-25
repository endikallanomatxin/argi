--
-- Baseline owning path type.
--
-- v1 keeps path semantics intentionally simple and POSIX-oriented:
-- components are separated by '/' and the type is mostly a thin owner
-- around `String` plus a handful of helpers commonly needed by the core.
--
Path : Type = (
    .text: String
)

path_is_separator(
    .byte: UInt8,
) -> (.ok: Bool) := {
    ok = byte == 47
}

path_last_separator_index(
    .view: &StringView,
) -> (.value: ?UIntNative) := {
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
    .view: &StringView,
    .start: UIntNative,
    .length: UIntNative,
) -> (.out: StringView) := {
    out = (
        .data = view&.data + start,
        .length = length,
    )
}

init(
    .p: $&Path,
    .text: String,
) -> () #trusted_temporal := {
    p& = (
        .text = text,
    )
}

init(
    .p: $&Path,
    .view: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () #trusted_temporal := {
    text :: String = String(.allocator = allocator, .capacity = view.length)
    pushed ::= push_view(.self = $&text, .view = view)
    match pushed {
        ..ok _ {
        }
        ..error _ {
        }
    }
    p& = (
        .text = text,
    )
}

path_with_view(
    .view: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Path, .reasons: (..out_of_memory))) := {
    created ::= string_with_capacity(.allocator = allocator, .capacity = view.length)
    match created {
        ..ok payload {
            text ::= payload
            pushed ::= push_view(.self = $&text, .view = view, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok (.text = text)
                }
                ..error _ {
                    deinit(.self = $&text, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

deinit(
    .self: $&Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () #invalidates(self) #invalidates_dependency(self, text.allocation.data) := {
    deinit(.self = $&self&.text, .allocator = allocator)
}

copy(
    .self: Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.out: Path) := {
    out = (
        .text = copy(.self = self.text, .allocator = allocator),
    )
}

as_view(
    .self: &Path,
) -> (.view: StringView) := {
    view = as_view(.self = &self&.text)
}

as_c_string(
    .self: &Path,
) -> (.text: &Char) := {
    text = as_c_string(.self = &self&.text)
}

is_absolute(
    .self: &Path,
) -> (.ok: Bool) := {
    view ::= as_view(.self = self)
    if view.length == 0 {
        ok = false
        return
    }

    ok = path_is_separator(.byte = bytes_get(.view = &view, .index = 0).byte).ok
}

file_name(
    .self: &Path,
) -> (.value: ?StringView) := {
    view ::= as_view(.self = self)
    if view.length == 0 {
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
            value = ..some(.value = string_view_slice(.view = &view, .start = start, .length = view.length - start))
        }
        ..none {
            value = ..some(.value = view)
        }
    }
}

parent(
    .self: &Path,
) -> (.value: ?StringView) := {
    view ::= as_view(.self = self)
    sep_index ::= path_last_separator_index(.view = &view).value
    match sep_index {
        ..some payload {
            if payload.value == 0 {
                value = ..some(.value = string_view_slice(.view = &view, .start = 0, .length = 1))
                return
            }
            value = ..some(.value = string_view_slice(.view = &view, .start = 0, .length = payload.value))
        }
        ..none {
            value = ..none
        }
    }
}

extension(
    .self: &Path,
) -> (.value: ?StringView) := {
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
                    value = ..some(.value = string_view_slice(.view = &file_view, .start = i, .length = file_view.length - i))
                    return
                }
            }

            value = ..none
        }
    }
}

join_views(
    .left: &StringView,
    .right: &StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Path, .reasons: (..out_of_memory))) := {
    target_capacity ::= left&.length + right&.length
    if left&.length > 0 and right&.length > 0 {
        if path_is_separator(.byte = bytes_get(.view = left, .index = left&.length - 1).byte).ok {
        } else {
            target_capacity = target_capacity + 1
        }
    }

    created ::= string_with_capacity(.allocator = allocator, .capacity = target_capacity)
    match created {
        ..ok payload {
            text ::= payload

            pushed_left ::= push_view(.self = $&text, .view = left&, .allocator = allocator)
            match pushed_left {
                ..ok _ {
                }
                ..error _ {
                    deinit(.self = $&text, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                    return
                }
            }

            if left&.length > 0 and right&.length > 0 {
                if path_is_separator(.byte = bytes_get(.view = left, .index = left&.length - 1).byte).ok {
                } else {
                    pushed_sep ::= push_byte(.self = $&text, .byte = 47, .allocator = allocator)
                    match pushed_sep {
                        ..ok _ {
                        }
                        ..error _ {
                            deinit(.self = $&text, .allocator = allocator)
                            result = ..error(.reason = ..out_of_memory)
                            return
                        }
                    }
                }
            }

            pushed_right ::= push_view(.self = $&text, .view = right&, .allocator = allocator)
            match pushed_right {
                ..ok _ {
                    result = ..ok (.text = text)
                }
                ..error _ {
                    deinit(.self = $&text, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

join(
    .left: &Path,
    .right: &Path,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Path, .reasons: (..out_of_memory))) := {
    left_view ::= as_view(.self = left)
    right_view ::= as_view(.self = right)
    result = join_views(.left = &left_view, .right = &right_view, .allocator = allocator)
}

operator ==(
    .left: &Path,
    .right: &Path,
) -> (.ok: Bool) := {
    ok = path_equals(.left = left, .right = right).ok
}

path_equals(
    .left: &Path,
    .right: &Path,
) -> (.ok: Bool) := {
    left_view ::= as_view(.self = left)
    right_view ::= as_view(.self = right)
    ok = left_view == right_view
}
