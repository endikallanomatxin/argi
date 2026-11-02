HttpVersion: Type = (..http10, ..http11)

implement ImplicitlyCopyable#(HttpVersion) ()

RequestHead := (
    .bytes        : ArrayView#(.t: UInt8)
    .method       : ArrayView#(.t: UInt8)
    .target       : ArrayView#(.t: UInt8)
    .version      : HttpVersion
    .framing      : BodyFraming
    .header_count : UIntNative
    ._headers_at  : UIntNative
)

implement ImplicitlyCopyable#(RequestHead) ()

_ipv6_valid := (.bytes: ArrayView#(.t: UInt8), .start: UIntNative, .end: UIntNative) -> (
    .ok : Bool = false
) {
    i ::= start
    groups :: UIntNative = 0
    compressed ::= false
    while i < end {
        if _byte(.bytes = bytes, .index = i).value == 58 {
            if compressed or end - i < 2 { return }
            if _byte(.bytes = bytes, .index = [i + 1]).value != 58 { return }
            compressed = true
            i = i + 2
            if i == end { break }
        }
        digits :: UIntNative = 0
        while i < end {
            c ::= _byte(.bytes = bytes, .index = i).value
            if c == 58 { break }
            if [[c >= 48 and c <= 57] or [c >= 65 and c <= 70] or [c >= 97 and c <= 102]] {
            } else {
                return
            }
            digits = digits + 1
            if digits > 4 { return }
            i = i + 1
        }
        if digits == 0 { return }
        groups = groups + 1
        if groups > 8 { return }
        if i < end {
            if end - i >= 2 {
                if _byte(.bytes = bytes, .index = [i + 1]).value == 58 { continue }
            }
            i = i + 1
            if i == end { return }
        }
    }
    ok = [compressed and groups < 8] or [compressed == false and groups == 8]
}

-- Authority validation accepts a reg-name or bracketed IP literal, with an
-- optional decimal port. It rejects delimiters that could change routing.
_authority_valid := (.bytes: ArrayView#(.t: UInt8)) -> (.ok: Bool = false) {
    size ::= length(&bytes).count
    if size == 0 { return }
    i :: UIntNative = 0
    if _byte(.bytes = bytes, .index = 0).value == 91 {
        i = 1
        start ::= i
        while i < size {
            c ::= _byte(.bytes = bytes, .index = i).value
            if c == 93 { break }
            if [
                [c >= 48 and c <= 57]
                or [c >= 65 and c <= 70]
                or [c >= 97 and c <= 102]
                or c == 58
                or c == 46
            ] {
            } else {
                return
            }
            i = i + 1
        }
        if i == start or i == size { return }
        if _ipv6_valid(.bytes = bytes, .start = start, .end = i).ok == false { return }
        i = i + 1
    } else {
        while i < size {
            c ::= _byte(.bytes = bytes, .index = i).value
            if c == 58 { break }
            if [
                [c >= 48 and c <= 57]
                or [c >= 65 and c <= 90]
                or [c >= 97 and c <= 122]
                or c == 45
                or c == 46
                or c == 95
                or c == 126
            ] {
            } else {
                return
            }
            i = i + 1
        }
        if i == 0 { return }
    }
    if i == size {
        ok = true
        return
    }
    if _byte(.bytes = bytes, .index = i).value != 58 { return }
    i = i + 1
    if i == size { return }
    port :: UIntNative = 0
    while i < size {
        c ::= _byte(.bytes = bytes, .index = i).value
        if c < 48 or c > 57 { return }
        digit ::= [c - 48] | convert#(.to: UIntNative)(_)
        if port > 6553 { return }
        port = port * 10 + digit
        if port > 65535 { return }
        i = i + 1
    }
    ok = true
}

_exact_equal := (.bytes: ArrayView#(.t: UInt8), .text: StringView) -> (.ok: Bool = false) {
    size ::= length(&bytes).count
    if size != byte_length(&text).count { return }
    i :: UIntNative = 0
    while i < size {
        if [
            _byte(.bytes = bytes, .index = i).value
            != unwrap_or_abort(.value = bytes_get(.view = &text, .index = i))
        ] { return }
        i = i + 1
    }
    ok = true
}

_target_path_valid := (.target: ArrayView#(.t: UInt8), .start: UIntNative) -> (
    .ok : Bool = false
) {
    size ::= length(&target).count
    i ::= start
    while i < size {
        c ::= _byte(.bytes = target, .index = i).value
        if c == 37 {
            if size - i < 3 { return }
            j ::= i + 1
            while j < i + 3 {
                digit ::= _byte(.bytes = target, .index = j).value
                if [
                    [digit >= 48 and digit <= 57]
                    or [digit >= 65 and digit <= 70]
                    or [digit >= 97 and digit <= 102]
                ] {
                } else {
                    return
                }
                j = j + 1
            }
            i = i + 3
            continue
        }
        if [
            [c >= 48 and c <= 57]
            or [c >= 65 and c <= 90]
            or [c >= 97 and c <= 122]
            or c == 45
            or c == 46
            or c == 95
            or c == 126
            or c == 33
            or c == 36
            or c == 38
            or c == 39
            or c == 40
            or c == 41
            or c == 42
            or c == 43
            or c == 44
            or c == 59
            or c == 61
            or c == 58
            or c == 64
            or c == 47
            or c == 63
        ] {
        } else {
            return
        }
        i = i + 1
    }
    ok = true
}

_target_valid := (.target: ArrayView#(.t: UInt8), .method: ArrayView#(.t: UInt8)) -> (
    .ok : Bool = false
) {
    size ::= length(&target).count
    if size == 0 { return }
    if _exact_equal(.bytes = method, .text = "CONNECT").ok { return }
    first ::= _byte(.bytes = target, .index = 0).value
    if first == 42 {
        ok = size == 1 and _exact_equal(.bytes = method, .text = "OPTIONS").ok
        return
    }
    if first == 47 {
        ok = _target_path_valid(.target = target, .start = 0).ok
        return
    }
    -- CONNECT authority-form is intentionally unsupported.
    authority_start :: UIntNative = 0
    if size >= 7 {
        prefix ::= _slice(.bytes = target, .start = 0, .end = 7).value
        if _ascii_equal(.bytes = prefix, .text = "http://").ok { authority_start = 7 }
    }
    if size >= 8 and authority_start == 0 {
        prefix ::= _slice(.bytes = target, .start = 0, .end = 8).value
        if _ascii_equal(.bytes = prefix, .text = "https://").ok { authority_start = 8 }
    }
    if authority_start == 0 { return }
    i ::= authority_start
    while i < size {
        c ::= _byte(.bytes = target, .index = i).value
        if c == 47 or c == 63 { break }
        i = i + 1
    }
    authority ::= _slice(.bytes = target, .start = authority_start, .end = i).value
    ok = [
        _authority_valid(.bytes = authority).ok
        and _target_path_valid(.target = target, .start = i).ok
    ]
}

method_is := (.self: &RequestHead, .method: StringView) -> (.ok: Bool) {
    ok = _exact_equal(.bytes = self&.method, .text = method).ok
}

_version_equal := (.bytes: ArrayView#(.t: UInt8), .last: UInt8) -> (.ok: Bool = false) {
    if length(&bytes).count != 8 { return }
    expected: StringView = "HTTP/1."
    i :: UIntNative = 0
    while i < 7 {
        if [
            _byte(.bytes = bytes, .index = i).value
            != unwrap_or_abort(.value = bytes_get(.view = &expected, .index = i))
        ] { return }
        i = i + 1
    }
    ok = _byte(.bytes = bytes, .index = 7).value == last
}

-- Parse a complete request head from initialized bytes. The returned views borrow
-- the input
-- Bytes following the terminating empty line are not included.
parse_request := (.bytes: ArrayView#(.t: UInt8), .limits: Limits = Limits()) -> (
    .result : Errable#(RequestHead, HttpReasons)
) {
    size ::= length(&bytes).count
    end :: UIntNative = 0
    found ::= false
    while end < size {
        if end >= limits.max_head_bytes {
            result = ..error(.reason = ..head_too_large)
            return
        }
        byte ::= _byte(.bytes = bytes, .index = end).value
        if byte == 10 {
            if end == 0 or _byte(.bytes = bytes, .index = [end - 1]).value != 13 {
                result = ..error(.reason = ..invalid_request)
                return
            }
            if end >= 3 {
                if [
                    _byte(.bytes = bytes, .index = [end - 2]).value == 10
                    and _byte(.bytes = bytes, .index = [end - 3]).value == 13
                ] {
                    end = end + 1
                    found = true
                    break
                }
            }
        } else if byte == 13 {
            if end + 1 < size {
                if _byte(.bytes = bytes, .index = [end + 1]).value != 10 {
                    result = ..error(.reason = ..invalid_request)
                    return
                }
            }
        }
        end = end + 1
    }
    if found == false {
        if size >= limits.max_head_bytes {
            result = ..error(.reason = ..head_too_large)
        } else {
            result = ..error(.reason = ..unexpected_eof)
        }
        return
    }
    head ::= _slice(.bytes = bytes, .start = 0, .end = end).value
    i :: UIntNative = 0
    while i < end {
        if _byte(.bytes = head, .index = i).value == 32 { break }
        if _token(.byte = _byte(.bytes = head, .index = i).value).ok == false {
            result = ..error(.reason = ..invalid_request)
            return
        }
        i = i + 1
    }
    if i == 0 or i == end {
        result = ..error(.reason = ..invalid_request)
        return
    }
    method ::= _slice(.bytes = head, .start = 0, .end = i).value
    start ::= i + 1
    i = start
    while i < end {
        byte ::= _byte(.bytes = head, .index = i).value
        if byte == 32 { break }
        if byte <= 32 or byte >= 127 or byte == 35 {
            result = ..error(.reason = ..invalid_request)
            return
        }
        i = i + 1
    }
    if i == start or i == end {
        result = ..error(.reason = ..invalid_request)
        return
    }
    target ::= _slice(.bytes = head, .start = start, .end = i).value
    if _target_valid(.target = target, .method = method).ok == false {
        result = ..error(.reason = ..invalid_request)
        return
    }
    start = i + 1
    i = start
    while i < end {
        if _byte(.bytes = head, .index = i).value == 13 { break }
        i = i + 1
    }
    version_bytes ::= _slice(.bytes = head, .start = start, .end = i).value
    version :: HttpVersion = ..http11
    if _version_equal(.bytes = version_bytes, .last = 49).ok {
        version = ..http11
    } else if _version_equal(.bytes = version_bytes, .last = 48).ok {
        version = ..http10
    } else {
        result = ..error(.reason = ..invalid_request)
        return
    }
    i = i + 2
    headers_at ::= i
    count :: UIntNative = 0
    host_seen ::= false
    length_seen ::= false
    transfer_seen ::= false
    body_length :: UIntNative = 0
    while i + 1 < end {
        if _byte(.bytes = head, .index = i).value == 13 { break }
        count = count + 1
        if count > limits.max_headers {
            result = ..error(.reason = ..too_many_headers)
            return
        }
        start = i
        while i < end {
            byte ::= _byte(.bytes = head, .index = i).value
            if byte == 58 { break }
            if _token(.byte = byte).ok == false {
                result = ..error(.reason = ..invalid_header)
                return
            }
            i = i + 1
        }
        if i == start or i == end {
            result = ..error(.reason = ..invalid_header)
            return
        }
        name ::= _slice(.bytes = head, .start = start, .end = i).value
        i = i + 1
        start = i
        while i < end {
            byte ::= _byte(.bytes = head, .index = i).value
            if byte == 13 { break }
            if [byte < 32 and byte != 9] or byte == 127 {
                result = ..error(.reason = ..invalid_header)
                return
            }
            i = i + 1
        }
        value_end ::= i
        while start < value_end {
            byte ::= _byte(.bytes = head, .index = start).value
            if byte != 32 and byte != 9 { break }
            start = start + 1
        }
        while value_end > start {
            byte ::= _byte(.bytes = head, .index = [value_end - 1]).value
            if byte != 32 and byte != 9 { break }
            value_end = value_end - 1
        }
        value ::= _slice(.bytes = head, .start = start, .end = value_end).value
        if _ascii_equal(.bytes = name, .text = "host").ok {
            if host_seen or _authority_valid(.bytes = value).ok == false {
                result = ..error(.reason = ..invalid_header)
                return
            }
            host_seen = true
        }
        if _ascii_equal(.bytes = name, .text = "expect").ok {
            result = ..error(.reason = ..unsupported_expectation)
            return
        }
        if _ascii_equal(.bytes = name, .text = "content-length").ok {
            if length_seen or start == value_end {
                result = ..error(.reason = ..invalid_framing)
                return
            }
            length_seen = true
            j ::= start
            while j < value_end {
                byte ::= _byte(.bytes = head, .index = j).value
                if byte < 48 or byte > 57 {
                    result = ..error(.reason = ..invalid_framing)
                    return
                }
                digit ::= [byte - 48] | convert#(.to: UIntNative)(_)
                if body_length > limits.max_body_bytes / 10 {
                    result = ..error(.reason = ..body_too_large)
                    return
                }
                body_length = body_length * 10
                if digit > limits.max_body_bytes - body_length {
                    result = ..error(.reason = ..body_too_large)
                    return
                }
                body_length = body_length + digit
                j = j + 1
            }
        }
        if _ascii_equal(.bytes = name, .text = "transfer-encoding").ok {
            if transfer_seen {
                result = ..error(.reason = ..invalid_framing)
                return
            }
            transfer_seen = true
            if _ascii_equal(.bytes = value, .text = "chunked").ok == false {
                result = ..error(.reason = ..unsupported_transfer_encoding)
                return
            }
        }
        i = i + 2
    }
    if is(.value = version, .variant = ..http11) and host_seen == false {
        result = ..error(.reason = ..invalid_header)
        return
    }
    if transfer_seen and is(.value = version, .variant = ..http10) {
        result = ..error(.reason = ..invalid_framing)
        return
    }
    if length_seen and transfer_seen {
        result = ..error(.reason = ..invalid_framing)
        return
    }
    framing :: BodyFraming = ..none
    if length_seen { framing = ..fixed(.length = body_length) }
    if transfer_seen { framing = ..chunked }
    result = ..ok(
        .bytes        = head
        .method       = method
        .target       = target
        .version      = version
        .framing      = framing
        .header_count = count
        ._headers_at  = headers_at
    )
}
