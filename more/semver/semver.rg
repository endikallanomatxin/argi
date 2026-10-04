-- Validated borrowed text keeps unlimited SemVer numeric components without
-- allocation or integer overflow. Private boundaries always describe _text.
VersionView: Type = (
    ._text      : StringView
    ._major_end : UIntNative
    ._minor_end : UIntNative
    ._patch_end : UIntNative
    ._pre_end   : UIntNative
)

VersionView implements ImplicitlyCopyable

_digit(.byte: UInt8) -> (.ok: Bool) := { ok = byte >= 48 and byte <= 57 }

_numeric_end(.text: &StringView, .start: UIntNative) -> (.end: UIntNative, .ok: Bool) := {
    end = start
    while end < text&.length {
        if _digit(.byte = bytes_get(.view = text, .index = end).byte).ok {} else { break }
        end = end + 1
    }
    ok = end > start
    if end - start > 1 {
        if bytes_get(.view = text, .index = start).byte == 48 { ok = false }
    }
}

_identifiers_valid(.text: StringView, .allow_numeric_zeroes: Bool) -> (.ok: Bool) := {
    ok = false
    if text.length == 0 { return }
    start :: UIntNative = 0
    i :: UIntNative = 0
    numeric :: Bool = true
    while i <= text.length {
        boundary :: Bool = i == text.length
        if i < text.length { boundary = bytes_get(.view = &text, .index = i).byte == 46 }
        if boundary {
            if i == start { return }
            if numeric and allow_numeric_zeroes == false and i - start > 1 {
                if bytes_get(.view = &text, .index = start).byte == 48 { return }
            }
            if i == text.length { break }
            start = i + 1
            numeric = true
        } else {
            byte ::= bytes_get(.view = &text, .index = i).byte
            if _digit(.byte = byte).ok {} else {
                numeric = false
                if byte == 45 or [byte >= 65 and byte <= 90] or [byte >= 97 and byte <= 122] {} else {
                    return
                }
            }
        }
        i = i + 1
    }
    ok = true
}

parse(.text: StringView) -> (.result: Errable#(.t: VersionView, .reasons: (..invalid_input))) := {
    first ::= _numeric_end(.text = &text, .start = 0)
    if first.ok == false or first.end == text.length {
        result = ..error(.reason = ..invalid_input)
        return
    }
    if bytes_get(.view = &text, .index = first.end).byte != 46 {
        result = ..error(.reason = ..invalid_input)
        return
    }
    second ::= _numeric_end(.text = &text, .start = first.end + 1)
    if second.ok == false or second.end == text.length {
        result = ..error(.reason = ..invalid_input)
        return
    }
    if bytes_get(.view = &text, .index = second.end).byte != 46 {
        result = ..error(.reason = ..invalid_input)
        return
    }
    third ::= _numeric_end(.text = &text, .start = second.end + 1)
    if third.ok == false {
        result = ..error(.reason = ..invalid_input)
        return
    }
    pre_end :: UIntNative = third.end
    if third.end < text.length {
        if bytes_get(.view = &text, .index = third.end).byte == 45 {
            pre_end = third.end + 1
            while pre_end < text.length {
                if bytes_get(.view = &text, .index = pre_end).byte == 43 { break }
                pre_end = pre_end + 1
            }
            pre ::= string_view_slice(
                .view   = &text
                .start  = third.end + 1
                .length = pre_end - third.end - 1
            )
            if _identifiers_valid(.text = pre, .allow_numeric_zeroes = false).ok {} else {
                result = ..error(.reason = ..invalid_input)
                return
            }
        }
    }
    if pre_end < text.length {
        if bytes_get(.view = &text, .index = pre_end).byte != 43 {
            result = ..error(.reason = ..invalid_input)
            return
        }
        build ::= string_view_slice(
            .view   = &text
            .start  = pre_end + 1
            .length = text.length - pre_end - 1
        )
        if _identifiers_valid(.text = build, .allow_numeric_zeroes = true).ok {} else {
            result = ..error(.reason = ..invalid_input)
            return
        }
    }
    result = ..ok(
        ._text      = text
        ._major_end = first.end
        ._minor_end = second.end
        ._patch_end = third.end
        ._pre_end   = pre_end
    )
}

VersionView init(
        .text : StringView
    ) -> (
        .result : Errable#(
            .t       : VersionView,
            .reasons : (..invalid_input)
        )
    ) := {
    result = parse(.text = text)
}

as_view(.self: &VersionView) -> (.text: StringView) := { text = self&._text }

major(.self: &VersionView) -> (.text: StringView) := {
    text = string_view_slice(.view = &self&._text, .start = 0, .length = self&._major_end)
}

minor(.self: &VersionView) -> (.text: StringView) := {
    text = string_view_slice(
        .view   = &self&._text
        .start  = self&._major_end + 1
        .length = self&._minor_end - self&._major_end - 1
    )
}

patch(.self: &VersionView) -> (.text: StringView) := {
    text = string_view_slice(
        .view   = &self&._text
        .start  = self&._minor_end + 1
        .length = self&._patch_end - self&._minor_end - 1
    )
}

pre_release(.self: &VersionView) -> (.text: StringView) := {
    if self&._pre_end == self&._patch_end {
        text = string_view_slice(.view = &self&._text, .start = 0, .length = 0)
        return
    }
    text = string_view_slice(
        .view   = &self&._text
        .start  = self&._patch_end + 1
        .length = self&._pre_end - self&._patch_end - 1
    )
}

build_metadata(.self: &VersionView) -> (.text: StringView) := {
    if self&._pre_end == self&._text.length {
        text = string_view_slice(.view = &self&._text, .start = 0, .length = 0)
        return
    }
    text = string_view_slice(
        .view   = &self&._text
        .start  = self&._pre_end + 1
        .length = self&._text.length - self&._pre_end - 1
    )
}

_lexical_compare(.left: StringView, .right: StringView) -> (.order: Int32) := {
    i :: UIntNative = 0
    while i < left.length and i < right.length {
        a ::= bytes_get(.view = &left, .index = i).byte
        b ::= bytes_get(.view = &right, .index = i).byte
        if a < b {
            order = -1
            return
        }
        if a > b {
            order = 1
            return
        }
        i = i + 1
    }
    order = 0
    if left.length < right.length { order = -1 }
    if left.length > right.length { order = 1 }
}

-- Validated numeric text has no leading zeroes. Length comparison therefore
-- establishes magnitude before a same-length lexical comparison.
_numeric_compare(.left: StringView, .right: StringView) -> (.order: Int32) := {
    if left.length < right.length {
        order = -1
        return
    }
    if left.length > right.length {
        order = 1
        return
    }
    order = _lexical_compare(.left = left, .right = right).order
}

_identifier_end(.text: &StringView, .start: UIntNative) -> (.end: UIntNative, .numeric: Bool) := {
    end = start
    numeric = true
    while end < text&.length {
        byte ::= bytes_get(.view = text, .index = end).byte
        if byte == 46 { break }
        if _digit(.byte = byte).ok {} else { numeric = false }
        end = end + 1
    }
}

_pre_compare(.left: StringView, .right: StringView) -> (.order: Int32) := {
    order = 0
    if left.length == 0 {
        if right.length > 0 { order = 1 }
        return
    }
    if right.length == 0 {
        order = -1
        return
    }
    a :: UIntNative = 0
    b :: UIntNative = 0
    while a < left.length and b < right.length {
        ae ::= _identifier_end(.text = &left, .start = a)
        be ::= _identifier_end(.text = &right, .start = b)
        if ae.numeric and be.numeric == false {
            order = -1
            return
        }
        if ae.numeric == false and be.numeric {
            order = 1
            return
        }
        av ::= string_view_slice(.view = &left, .start = a, .length = ae.end - a)
        bv ::= string_view_slice(.view = &right, .start = b, .length = be.end - b)
        if ae.numeric { order = _numeric_compare(.left = av, .right = bv).order } else {
            order = _lexical_compare(.left = av, .right = bv).order
        }
        if order != 0 { return }
        if ae.end == left.length or be.end == right.length {
            if ae.end < left.length { order = 1 }
            if be.end < right.length { order = -1 }
            return
        }
        a = ae.end + 1
        b = be.end + 1
    }
}

compare(.left: &VersionView, .right: &VersionView) -> (.order: Int32) := {
    order = _numeric_compare(.left = major(.self = left).text, .right = major(.self = right).text).order
    if order != 0 { return }
    order = _numeric_compare(.left = minor(.self = left).text, .right = minor(.self = right).text).order
    if order != 0 { return }
    order = _numeric_compare(.left = patch(.self = left).text, .right = patch(.self = right).text).order
    if order != 0 { return }
    order = _pre_compare(
        .left  = pre_release(.self = left).text
        .right = pre_release(.self = right).text
    ).order
}

same_precedence(.left: &VersionView, .right: &VersionView) -> (.ok: Bool) := {
    ok = compare(.left = left, .right = right).order == 0
}

equals(.left: &VersionView, .right: &VersionView) -> (.ok: Bool) := {
    ok = left&._text == right&._text
}

operator == (.left: &VersionView, .right: &VersionView) -> (.ok: Bool) := {
    ok = equals(.left = left, .right = right).ok
}

operator != (.left: &VersionView, .right: &VersionView) -> (.ok: Bool) := {
    ok = equals(.left = left, .right = right).ok == false
}

format(
        .value     : &VersionView,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..out_of_memory)
        )
    ) := {
    result = format(.value = as_view(.self = value).text, .allocator = allocator)
}

format_into(
        .out       : $&String,
        .value     : &VersionView,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t : Void,

            .reasons : (..out_of_memory)
        )
    ) := {
    result = format_into(.out = out, .value = as_view(.self = value).text, .allocator = allocator)
}

format_into(
        .out   : $&Writer,
        .value : &VersionView
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..stream_write_failed, ..stream_flush_failed)
        )
    ) := {
    result = write(.self = out, .text = as_view(.self = value).text)
}
