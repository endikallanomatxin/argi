BodyFraming: Type = (..none, ..fixed(.length: UIntNative), ..chunked)

implement ImplicitlyCopyable#(BodyFraming) ()

-- Body state contains counters only. Payload storage is always supplied by the
-- caller, independently of the immutable request-head storage.
_ChunkPhase: Type = (
    ..size,
    ..name_start,
    ..name,
    ..value_start,
    ..quoted,
    ..token,
    ..after_size,
    ..after_name,
    ..after_value,
    ..padding
)

_BodyState := (
    ._framing   : BodyFraming
    ._remaining : UIntNative
    ._total     : UIntNative
    ._limits    : Limits
    ._footer    : Bool
    ._done      : Bool
    ._failed    : Bool
)

_body_state := (.head: &RequestHead, .limits: Limits = Limits()) -> (.state: _BodyState) {
    count :: UIntNative = 0
    done ::= false
    match head&.framing {
        ..none { done = true }
        ..fixed item {
            count = item.length
            done = count == 0
        }
        ..chunked {}
    }
    state = (
        ._framing   = head&.framing
        ._remaining = count
        ._total     = 0
        ._limits    = limits
        ._footer    = false
        ._done      = done
        ._failed    = false
    )
}

_body_state_finished := (.self: &_BodyState) -> (.ok: Bool) {
    ok = [self&._done and self&._failed == false]
}

_body_byte := #(.R: Type: BlockReader#(R)) (.reader: $&R) -> (
    .result : Errable#(UInt8, HttpReasons)
) {
    storage :: [1]UInt8 = (0)
    got ::= BlockReader#().read_block(reader, .buffer = view($&storage))!
    if got > 1 { abort }
    if got == 0 {
        result = ..error(.reason = ..unexpected_eof)
        return
    }
    result = ..ok storage[0]
}

_body_crlf := #(.R: Type: BlockReader#(R)) (.reader: $&R) -> (
    .result : Errable#(Void, HttpReasons) = ..ok Void()
) {
    if _body_byte(.reader = reader)! != 13 {
        result = ..error(.reason = ..invalid_chunk)
        return
    }
    if _body_byte(.reader = reader)! != 10 { result = ..error(.reason = ..invalid_chunk) }
}

-- Chunk extensions are bounded and validated even though their values are not
-- exposed. The state machine accepts token and quoted-string extension values.
_chunk_size := #(.R: Type: BlockReader#(R)) (
    .reader: $&R, .limit: UIntNative, .budget: UIntNative
) -> (.result: Errable#(UIntNative, HttpReasons)) {
    count :: UIntNative = 0
    value :: UIntNative = 0
    digits :: UIntNative = 0
    phase :: _ChunkPhase = ..size
    escaped ::= false
    while true {
        if count >= limit {
            result = ..error(.reason = ..invalid_chunk)
            return
        }
        byte ::= _body_byte(.reader = reader)!
        count = count + 1
        if byte == 13 {
            if [
                digits == 0
                or phase == ..name_start
                or phase == ..value_start
                or phase == ..quoted
                or phase == ..after_size
                or phase == ..after_name
                or phase == ..padding
            ] {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
            if count >= limit {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
            if _body_byte(.reader = reader)! != 10 {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
            result = ..ok value
            return
        }
        if phase == ..size {
            digit :: UIntNative = 16
            if byte >= 48 and byte <= 57 { digit = [byte - 48] | convert#(.to: UIntNative)(_) }
            if byte >= 65 and byte <= 70 { digit = [byte - 55] | convert#(.to: UIntNative)(_) }
            if byte >= 97 and byte <= 102 {
                digit = [byte - 87] | convert#(.to: UIntNative)(_)
            }
            if digit < 16 {
                if value > budget / 16 {
                    result = ..error(.reason = ..body_too_large)
                    return
                }
                value = value * 16
                if digit > budget - value {
                    result = ..error(.reason = ..body_too_large)
                    return
                }
                value = value + digit
                digits = digits + 1
            } else if digits != 0 and byte == 59 {
                phase = ..name_start
            } else if digits != 0 and [byte == 32 or byte == 9] {
                phase = ..after_size
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..name_start {
            if byte == 32 or byte == 9 {
            } else if _token(.byte = byte).ok {
                phase = ..name
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..name {
            if _token(.byte = byte).ok {
            } else if byte == 61 {
                phase = ..value_start
            } else if byte == 59 {
                phase = ..name_start
            } else if byte == 32 or byte == 9 {
                phase = ..after_name
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..value_start {
            if byte == 32 or byte == 9 {
            } else if byte == 34 {
                phase = ..quoted
            } else if _token(.byte = byte).ok {
                phase = ..token
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..quoted {
            if escaped {
                if [byte < 32 and byte != 9] or byte == 127 {
                    result = ..error(.reason = ..invalid_chunk)
                    return
                }
                escaped = false
            } else if byte == 92 {
                escaped = true
            } else if byte == 34 {
                phase = ..after_value
            } else if [byte < 32 and byte != 9] or byte == 127 {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..token {
            if _token(.byte = byte).ok {
            } else if byte == 59 {
                phase = ..name_start
            } else if byte == 32 or byte == 9 {
                phase = ..padding
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..after_size {
            if byte == 32 or byte == 9 {
            } else if byte == 59 {
                phase = ..name_start
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else if phase == ..after_name {
            if byte == 32 or byte == 9 {
            } else if byte == 61 {
                phase = ..value_start
            } else if byte == 59 {
                phase = ..name_start
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        } else {
            if byte == 32 or byte == 9 {
                phase = ..padding
            } else if byte == 59 {
                phase = ..name_start
            } else {
                result = ..error(.reason = ..invalid_chunk)
                return
            }
        }
    }
}

-- Trailers are consumed and validated, but never merged into request headers.
-- Framing, routing, authentication and payload interpretation fields are banned.
_body_trailers := #(.R: Type: BlockReader#(R)) (.reader: $&R, .limits: Limits) -> (
    .result : Errable#(Void, HttpReasons) = ..ok Void()
) {
    total :: UIntNative = 0
    count :: UIntNative = 0
    while true {
        name :: [256]UInt8 = zeroed#(.t: [256]UInt8)()
        used :: UIntNative = 0
        colon ::= false
        line :: UIntNative = 0
        while true {
            if total >= limits.max_trailer_bytes {
                result = ..error(.reason = ..head_too_large)
                return
            }
            byte ::= _body_byte(.reader = reader)!
            total = total + 1
            if byte == 13 {
                if total >= limits.max_trailer_bytes {
                    result = ..error(.reason = ..head_too_large)
                    return
                }
                if _body_byte(.reader = reader)! != 10 {
                    result = ..error(.reason = ..invalid_chunk)
                    return
                }
                total = total + 1
                break
            }
            line = line + 1
            if colon == false {
                if byte == 58 {
                    if used == 0 {
                        result = ..error(.reason = ..invalid_header)
                        return
                    }
                    colon = true
                } else {
                    if _token(.byte = byte).ok == false or used == 256 {
                        result = ..error(.reason = ..invalid_header)
                        return
                    }
                    name[used] = byte
                    used = used + 1
                }
            } else if [byte < 32 and byte != 9] or byte == 127 {
                result = ..error(.reason = ..invalid_header)
                return
            }
        }
        if line == 0 { return }
        if colon == false {
            result = ..error(.reason = ..invalid_header)
            return
        }
        count = count + 1
        if count > limits.max_headers {
            result = ..error(.reason = ..too_many_headers)
            return
        }
        bytes ::= _slice(.bytes = view(&name), .start = 0, .end = used).value
        if [
            _ascii_equal(.bytes = bytes, .text = "content-length").ok
            or _ascii_equal(.bytes = bytes, .text = "transfer-encoding").ok
            or _ascii_equal(.bytes = bytes, .text = "host").ok
            or _ascii_equal(.bytes = bytes, .text = "connection").ok
            or _ascii_equal(.bytes = bytes, .text = "trailer").ok
            or _ascii_equal(.bytes = bytes, .text = "authorization").ok
            or _ascii_equal(.bytes = bytes, .text = "content-type").ok
            or _ascii_equal(.bytes = bytes, .text = "content-encoding").ok
        ] {
            result = ..error(.reason = ..invalid_header)
            return
        }
    }
}

_read_body := #(.R: Type: BlockReader#(R)) (
    .reader: $&R, .state: $&_BodyState, .buffer: MutableArrayView#(UInt8)
) -> (.result: Errable#(UIntNative, HttpReasons)) {
    if state&._done or length(&buffer).count == 0 {
        result = ..ok 0
        return
    }
    if state&._remaining == 0 {
        if state&._footer {
            _body_crlf(.reader = reader)!
            state&._footer = false
        }
        size ::= _chunk_size(
            .reader = reader
            .limit  = state&._limits.max_chunk_line_bytes
            .budget = [state&._limits.max_body_bytes - state&._total]
        )!
        if size == 0 {
            _body_trailers(.reader = reader, .limits = state&._limits)!
            state&._done = true
            result = ..ok 0
            return
        }
        state&._remaining = size
    }
    count ::= length(&buffer).count
    if count > state&._remaining { count = state&._remaining }
    if count > state&._limits.max_body_bytes - state&._total {
        result = ..error(.reason = ..body_too_large)
        return
    }
    destination ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = count))
    got ::= BlockReader#().read_block(reader, .buffer = destination)!
    if got > count { abort }
    if got == 0 {
        result = ..error(.reason = ..unexpected_eof)
        return
    }
    state&._remaining = state&._remaining - got
    state&._total = state&._total + got
    if state&._remaining == 0 {
        match state&._framing {
            ..chunked { state&._footer = true }
            ..fixed _ { state&._done = true }
            ..none { state&._done = true }
        }
    }
    result = ..ok got
}

_read_body_state := #(.R: Type: BlockReader#(R)) (
    .reader: $&R, .state: $&_BodyState, .buffer: MutableArrayView#(UInt8)
) -> (.result: Errable#(UIntNative, HttpReasons)) {
    if state&._failed {
        result = ..error(.reason = ..invalid_state)
        return
    }
    match _read_body(.reader = reader, .state = state, .buffer = buffer) {
        ..ok count { result = ..ok count }
        ..error error {
            state&._failed = true
            result = ..error error
        }
    }
}
