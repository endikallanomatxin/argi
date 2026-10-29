-- Equal keys must feed identical byte streams to the same hasher. Composite
-- implementations must delimit variable-length fields to avoid losing boundaries.
Hashable#(.Key: Type, .State: Type: Hasher#(State)): Contract = (
    .hash_into : (.key: &Key, .hasher: $&State) -> ()
)

_hash_unsigned := #(.State: Type: Hasher#(State)) (
    .value: UInt64, .count: UIntNative, .hasher: $&State
) -> () {
    assume error_tracer ::= NoopErrorTracer() | to_virtual#(.contract: ErrorTracer)($&_) | $&_
    storage ::= zeroed#(.t: [8]UInt8)()
    remaining ::= value
    index :: UIntNative = 0
    while index < count {
        storage[index] = unwrap_or_abort(.value = [[remaining % 256] | convert#(.to: UInt8)(_)])
        remaining = remaining / 256
        index = index + 1
    }
    bytes ::= unwrap_or_abort(.value = slice(&view(&storage), .start = 0, .count = count))
    Hasher#(State).write_bytes(hasher, .bytes = bytes)
}

_hash_signed := #(.State: Type: Hasher#(State)) (
    .value: Int64, .count: UIntNative, .hasher: $&State
) -> () {
    assume error_tracer ::= NoopErrorTracer() | to_virtual#(.contract: ErrorTracer)($&_) | $&_
    bits :: UInt64 = 0
    if value >= 0 {
        bits = unwrap_or_abort(.value = [value | convert#(.to: UInt64)(_)])
    } else {
        magnitude ::= unwrap_or_abort(.value = [[0 - [value + 1]] | convert#(.to: UInt64)(_)])
        bits = 18446744073709551615 - magnitude
    }
    _hash_unsigned(.value = bits, .count = count, .hasher = hasher)
}

_hash_text := #(.State: Type: Hasher#(State)) (.text: StringView, .hasher: $&State) -> () {
    assume error_tracer ::= NoopErrorTracer() | to_virtual#(.contract: ErrorTracer)($&_) | $&_
    extent ::= byte_length(&text) | convert#(.to: UInt64)(_)
    _hash_unsigned(.value = extent, .count = 8, .hasher = hasher)
    Hasher#(State).write_bytes(hasher, .bytes = string_bytes(.text = text))
}

implement#(.State: Type: Hasher#(State)) Hashable#(StringView, State) (
    .hash_into = (.key: &StringView, .hasher: $&State) -> () {
        _hash_text(.text = key&, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(String, State) (
    .hash_into = (.key: &String, .hasher: $&State) -> () {
        _hash_text(.text = view(key), .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(UInt8, State) (
    .hash_into = (.key: &UInt8, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: UInt64)(_)
        _hash_unsigned(.value = value, .count = 1, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(UInt16, State) (
    .hash_into = (.key: &UInt16, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: UInt64)(_)
        _hash_unsigned(.value = value, .count = 2, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(UInt32, State) (
    .hash_into = (.key: &UInt32, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: UInt64)(_)
        _hash_unsigned(.value = value, .count = 4, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(UInt64, State) (
    .hash_into = (.key: &UInt64, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: UInt64)(_)
        _hash_unsigned(.value = value, .count = 8, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(UIntNative, State) (
    .hash_into = (.key: &UIntNative, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: UInt64)(_)
        #if target_pointer_bits(64) {
            _hash_unsigned(.value = value, .count = 8, .hasher = hasher)
        } #else {
            #if target_pointer_bits(32) {
                _hash_unsigned(.value = value, .count = 4, .hasher = hasher)
            } #else {
                _hash_unsigned(.value = value, .count = 2, .hasher = hasher)
            }
        }
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(Int8, State) (
    .hash_into = (.key: &Int8, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: Int64)(_)
        _hash_signed(.value = value, .count = 1, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(Int16, State) (
    .hash_into = (.key: &Int16, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: Int64)(_)
        _hash_signed(.value = value, .count = 2, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(Int32, State) (
    .hash_into = (.key: &Int32, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: Int64)(_)
        _hash_signed(.value = value, .count = 4, .hasher = hasher)
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(Int64, State) (
    .hash_into = (.key: &Int64, .hasher: $&State) -> () {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        value ::= key&| convert#(.to: Int64)(_)
        _hash_signed(.value = value, .count = 8, .hasher = hasher)
    }
)
