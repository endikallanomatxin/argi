-- Components borrow the encoded source; decoding is an explicit allocation.
UriView: Type = (
    .scheme    : ?StringView
    .authority : ?StringView
    .path      : StringView
    .query     : ?StringView
    .fragment  : ?StringView
)

UriView implements ImplicitlyCopyable

_alpha(.byte: UInt8) -> (.ok: Bool) := {
    ok = [byte >= 65 and byte <= 90] or [byte >= 97 and byte <= 122]
}

_digit(.byte: UInt8) -> (.ok: Bool) := { ok = byte >= 48 and byte <= 57 }

_unreserved(.byte: UInt8) -> (.ok: Bool) := {
    ok = [
        _alpha(.byte = byte).ok
        or _digit(.byte = byte).ok
        or byte == 45
        or byte == 46
        or byte == 95
        or byte == 126
    ]
}

_subdelimiter(.byte: UInt8) -> (.ok: Bool) := {
    ok = [
        byte == 33
        or byte == 36
        or byte == 38
        or byte == 39
        or byte == 40
        or byte == 41
        or byte == 42
        or byte == 43
        or byte == 44
        or byte == 59
        or byte == 61
    ]
}

_hex(.byte: UInt8) -> (.value: UInt8, .ok: Bool = true) := {
    if _digit(.byte = byte).ok {
        value = byte - 48
        return
    }
    if byte >= 65 and byte <= 70 {
        value = byte - 55
        return
    }
    if byte >= 97 and byte <= 102 {
        value = byte - 87
        return
    }
    value = 0
    ok = false
}

_scheme_valid(.text: StringView) -> (.ok: Bool = false) := {
    if text.length == 0 { return }
    if _alpha(.byte = bytes_get(.view = &text, .index = 0).byte).ok == false { return }
    i :: UIntNative = 1
    while i < text.length {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if [
            _alpha(.byte = byte).ok
            or _digit(.byte = byte).ok
            or byte == 43
            or byte == 45
            or byte == 46
        ] {
        } else { return }
        i = i + 1
    }
    ok = true
}

_component_valid(.text: StringView, .kind: UInt8) -> (.ok: Bool = false) := {
    i :: UIntNative = 0
    while i < text.length {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if byte == 37 {
            if text.length - i < 3 { return }
            if [
                _hex(.byte = bytes_get(.view = &text, .index = i + 1).byte).ok == false
                or _hex(
                    .byte = bytes_get(
                        .view = &text

                        .index = i + 2
                    ).byte
                ).ok == false
            ] { return }
            i = i + 3
        } else {
            allowed ::= [
                _unreserved(.byte = byte).ok
                or _subdelimiter(.byte = byte).ok
                or byte == 58
                or byte == 64
            ]
            if kind == 0 { allowed = allowed or byte == 91 or byte == 93 }
            if kind == 1 or kind == 2 { allowed = allowed or byte == 47 }
            if kind == 2 { allowed = allowed or byte == 63 }
            if allowed == false { return }
            i = i + 1
        }
    }
    ok = true
}

_slice(.text: StringView, .start: UIntNative, .end: UIntNative) -> (.value: StringView) := {
    value = string_view_slice(.view = &text, .start = start, .length = end - start)
}

-- Delimiters are recognized before any decoding. Encoded separators remain data.
parse(.text: StringView) -> (.result: Errable#(.t: UriView, .reasons: (..invalid_input))) := {
    fragment_start ::= text.length
    i :: UIntNative = 0
    while i < text.length {
        if bytes_get(.view = &text, .index = i).byte == 35 {
            fragment_start = i
            break
        }
        i = i + 1
    }
    query_start ::= fragment_start
    i = 0
    while i < fragment_start {
        if bytes_get(.view = &text, .index = i).byte == 63 {
            query_start = i
            break
        }
        i = i + 1
    }
    scheme :: ?StringView = ..none
    authority :: ?StringView = ..none
    query :: ?StringView = ..none
    fragment :: ?StringView = ..none
    start :: UIntNative = 0
    i = 0
    while i < query_start {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if byte == 47 { break }
        if byte == 58 {
            candidate ::= _slice(.text = text, .start = 0, .end = i).value
            if _scheme_valid(.text = candidate).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            scheme = ..some(.value = candidate)
            start = i + 1
            break
        }
        i = i + 1
    }
    if query_start - start >= 2 {
        if [
            bytes_get(.view = &text, .index = start).byte == 47
            and bytes_get(
                .view  = &text
                .index = start + 1
            ).byte == 47
        ] {
            i = start + 2
            while i < query_start {
                if bytes_get(.view = &text, .index = i).byte == 47 { break }
                i = i + 1
            }
            candidate ::= _slice(.text = text, .start = start + 2, .end = i).value
            if _authority_valid(.text = candidate).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            authority = ..some(.value = candidate)
            start = i
        }
    }
    path ::= _slice(.text = text, .start = start, .end = query_start).value
    if _component_valid(.text = path, .kind = 1).ok == false {
        result = ..error(.reason = ..invalid_input)
        return
    }
    if query_start < fragment_start {
        candidate ::= _slice(.text = text, .start = query_start + 1, .end = fragment_start).value
        if _component_valid(.text = candidate, .kind = 2).ok == false {
            result = ..error(.reason = ..invalid_input)
            return
        }
        query = ..some(.value = candidate)
    }
    if fragment_start < text.length {
        candidate ::= _slice(.text = text, .start = fragment_start + 1, .end = text.length).value
        if _component_valid(.text = candidate, .kind = 2).ok == false {
            result = ..error(.reason = ..invalid_input)
            return
        }
        fragment = ..some(.value = candidate)
    }
    result = ..ok(
        .scheme    = scheme
        .authority = authority
        .path      = path
        .query     = query
        .fragment  = fragment
    )
}

_ipv4_valid(.text: StringView) -> (.ok: Bool = false) := {
    groups :: UIntNative = 0
    start :: UIntNative = 0
    i :: UIntNative = 0
    number :: UIntNative = 0
    while i <= text.length {
        boundary ::= i == text.length
        if i < text.length { boundary = bytes_get(.view = &text, .index = i).byte == 46 }
        if boundary {
            if i == start or i - start > 3 or number > 255 { return }
            if i - start > 1 and bytes_get(.view = &text, .index = start).byte == 48 { return }
            groups = groups + 1
            if i == text.length { break }
            start = i + 1
            number = 0
        } else {
            byte ::= bytes_get(.view = &text, .index = i).byte
            if _digit(.byte = byte).ok == false or i - start >= 3 { return }
            number = number * 10 + UIntNative(.value = byte - 48)
        }
        i = i + 1
    }
    ok = groups == 4
}

_ip_literal_valid(.text: StringView) -> (.ok: Bool = false) := {
    if text.length == 0 { return }
    first ::= bytes_get(.view = &text, .index = 0).byte
    if first == 118 or first == 86 {
        i :: UIntNative = 1
        while i < text.length {
            if _hex(.byte = bytes_get(.view = &text, .index = i).byte).ok == false { break }
            i = i + 1
        }
        if i == 1 or i == text.length { return }
        if bytes_get(.view = &text, .index = i).byte != 46 { return }
        i = i + 1
        if i == text.length { return }
        while i < text.length {
            byte ::= bytes_get(.view = &text, .index = i).byte
            if _unreserved(.byte = byte).ok or _subdelimiter(.byte = byte).ok or byte == 58 {} else {
                return
            }
            i = i + 1
        }
        ok = true
        return
    }
    groups :: UIntNative = 0
    compressed :: Bool = false
    i :: UIntNative = 0
    while i < text.length {
        if bytes_get(.view = &text, .index = i).byte == 58 {
            if compressed or text.length - i < 2 { return }
            if bytes_get(.view = &text, .index = i + 1).byte != 58 { return }
            compressed = true
            i = i + 2
            if i == text.length { break }
        }
        start ::= i
        dotted :: Bool = false
        while i < text.length {
            byte ::= bytes_get(.view = &text, .index = i).byte
            if byte == 58 { break }
            if byte == 46 { dotted = true }
            i = i + 1
        }
        if i == start { return }
        part ::= _slice(.text = text, .start = start, .end = i).value
        if dotted {
            if i != text.length or _ipv4_valid(.text = part).ok == false { return }
            groups = groups + 2
        } else {
            if part.length > 4 { return }
            j :: UIntNative = 0
            while j < part.length {
                if _hex(.byte = bytes_get(.view = &part, .index = j).byte).ok == false { return }
                j = j + 1
            }
            groups = groups + 1
        }
        if groups > 8 { return }
        if i < text.length {
            if text.length - i >= 2 {
                if bytes_get(.view = &text, .index = i + 1).byte == 58 { continue }
            }
            i = i + 1
            if i == text.length { return }
        }
    }
    ok = [compressed and groups < 8] or [compressed == false and groups == 8]
}

_authority_valid(.text: StringView) -> (.ok: Bool = false) := {
    if _component_valid(.text = text, .kind = 0).ok == false { return }
    host_start :: UIntNative = 0
    i :: UIntNative = 0
    while i < text.length {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if byte == 64 {
            if host_start != 0 { return }
            user ::= _slice(.text = text, .start = 0, .end = i).value
            if _component_valid(.text = user, .kind = 3).ok == false { return }
            host_start = i + 1
        }
        i = i + 1
    }
    host_end ::= text.length
    port_start ::= text.length
    if host_start < text.length {
        if bytes_get(.view = &text, .index = host_start).byte == 91 {
            i = host_start + 1
            while i < text.length {
                if bytes_get(.view = &text, .index = i).byte == 93 { break }
                i = i + 1
            }
            if i == text.length or i == host_start + 1 { return }
            literal ::= _slice(.text = text, .start = host_start + 1, .end = i).value
            if _ip_literal_valid(.text = literal).ok == false { return }
            host_end = i + 1
            if host_end < text.length {
                if bytes_get(.view = &text, .index = host_end).byte != 58 { return }
                port_start = host_end + 1
            }
        } else {
            i = host_start
            while i < text.length {
                byte ::= bytes_get(.view = &text, .index = i).byte
                if byte == 58 {
                    host_end = i
                    port_start = i + 1
                    break
                }
                if byte == 91 or byte == 93 { return }
                i = i + 1
            }
        }
    }
    i = port_start
    while i < text.length {
        if _digit(.byte = bytes_get(.view = &text, .index = i).byte).ok == false { return }
        i = i + 1
    }
    ok = true
}

-- Recompose already encoded components. Validation rejects delimiter injection
-- and ambiguous relative paths rather than silently changing their meaning.
build(
        .value     : UriView,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..invalid_input, ..out_of_memory)
        )
    ) := {
    if [
        is(.value = value.scheme, .variant = ..none)
        and is(
            .value   = value.authority
            .variant = ..none
        )
    ] {
        i :: UIntNative = 0
        while i < value.path.length {
            byte ::= bytes_get(.view = &value.path, .index = i).byte
            if byte == 47 { break }
            if byte == 58 {
                result = ..error(.reason = ..invalid_input)
                return
            }
            i = i + 1
        }
    }
    output ::= String(.allocator = allocator, .capacity = 0)!
    match value.scheme {
        ..none {}
        ..some item {
            if _scheme_valid(.text = item.value).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            push_view(.self = $&output, .view = item.value, .allocator = allocator)!
            push_byte(.self = $&output, .byte = 58, .allocator = allocator)!
        }
    }
    match value.authority {
        ..none {
            if value.path.length >= 2 {
                if [
                    bytes_get(.view = &value.path, .index = 0).byte == 47
                    and bytes_get(
                        .view = &value.path

                        .index = 1
                    ).byte == 47
                ] {
                    result = ..error(.reason = ..invalid_input)
                    return
                }
            }
        }
        ..some item {
            if _authority_valid(.text = item.value).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            if value.path.length > 0 {
                if bytes_get(.view = &value.path, .index = 0).byte != 47 {
                    result = ..error(.reason = ..invalid_input)
                    return
                }
            }
            push_view(.self = $&output, .view = "//", .allocator = allocator)!
            push_view(.self = $&output, .view = item.value, .allocator = allocator)!
        }
    }
    if _component_valid(.text = value.path, .kind = 1).ok == false {
        result = ..error(.reason = ..invalid_input)
        return
    }
    push_view(.self = $&output, .view = value.path, .allocator = allocator)!
    match value.query {
        ..none {}
        ..some item {
            if _component_valid(.text = item.value, .kind = 2).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            push_byte(.self = $&output, .byte = 63, .allocator = allocator)!
            push_view(.self = $&output, .view = item.value, .allocator = allocator)!
        }
    }
    match value.fragment {
        ..none {}
        ..some item {
            if _component_valid(.text = item.value, .kind = 2).ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            push_byte(.self = $&output, .byte = 35, .allocator = allocator)!
            push_view(.self = $&output, .view = item.value, .allocator = allocator)!
        }
    }
    result = ..ok ~output
}

encode_component(
        .text      : StringView,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..out_of_memory)
        )
    ) := {
    output ::= String(.allocator = allocator, .capacity = 0)!
    hex: StringView = "0123456789ABCDEF"
    i :: UIntNative = 0
    while i < text.length {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if _unreserved(.byte = byte).ok {
            push_byte(.self = $&output, .byte = byte, .allocator = allocator)!
        } else {
            push_byte(.self = $&output, .byte = 37, .allocator = allocator)!
            push_byte(
                .self      = $&output
                .byte      = bytes_get(.view = &hex, .index = UIntNative(.value = byte / 16)).byte
                .allocator = allocator
            )!
            push_byte(
                .self      = $&output
                .byte      = bytes_get(.view = &hex, .index = UIntNative(.value = byte % 16)).byte
                .allocator = allocator
            )!
        }
        i = i + 1
    }
    result = ..ok ~output
}

decode_component(
        .text      : StringView,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..invalid_input, ..out_of_memory)
        )
    ) := {
    output ::= String(.allocator = allocator, .capacity = 0)!
    i :: UIntNative = 0
    while i < text.length {
        byte ::= bytes_get(.view = &text, .index = i).byte
        if byte == 37 {
            if text.length - i < 3 {
                result = ..error(.reason = ..invalid_input)
                return
            }
            high ::= _hex(.byte = bytes_get(.view = &text, .index = i + 1).byte)
            low ::= _hex(.byte = bytes_get(.view = &text, .index = i + 2).byte)
            if high.ok == false or low.ok == false {
                result = ..error(.reason = ..invalid_input)
                return
            }
            byte = high.value * 16 + low.value
            i = i + 2
        }
        push_byte(.self = $&output, .byte = byte, .allocator = allocator)!
        i = i + 1
    }
    result = ..ok ~output
}

AuthorityView: Type = (.userinfo: ?StringView, .host: StringView, .port: ?StringView)

AuthorityView implements ImplicitlyCopyable

authority_parts(
        .text : StringView
    ) -> (
        .result : Errable#(
            .t       : AuthorityView,
            .reasons : (..invalid_input)
        )
    ) := {
    if _authority_valid(.text = text).ok == false {
        result = ..error(.reason = ..invalid_input)
        return
    }
    userinfo :: ?StringView = ..none
    port :: ?StringView = ..none
    start :: UIntNative = 0
    i :: UIntNative = 0
    while i < text.length {
        if bytes_get(.view = &text, .index = i).byte == 64 {
            userinfo = ..some(.value = _slice(.text = text, .start = 0, .end = i).value)
            start = i + 1
            break
        }
        i = i + 1
    }
    end ::= text.length
    i = start
    if i < text.length {
        if bytes_get(.view = &text, .index = i).byte == 91 {
            while bytes_get(.view = &text, .index = i).byte != 93 { i = i + 1 }
            i = i + 1
        }
    }
    while i < text.length {
        if bytes_get(.view = &text, .index = i).byte == 58 {
            end = i
            port = ..some(.value = _slice(.text = text, .start = i + 1, .end = text.length).value)
            break
        }
        i = i + 1
    }
    result = ..ok(
        .userinfo = userinfo
        .host     = _slice(.text = text, .start = start, .end = end).value
        .port     = port
    )
}
