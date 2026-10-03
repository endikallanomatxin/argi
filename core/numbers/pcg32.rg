-- PCG XSH-RR 64/32 with the standard single-stream increment. Split products
-- express its modulo-2^64 recurrence without weakening checked arithmetic.
Pcg32: Type = (
    ._state : UInt64
)
Pcg32 implements ImplicitlyCopyable

_pcg_advance(.state: UInt64) -> (.next: UInt64) := {
    low ::= state % 4294967296
    high ::= state / 4294967296
    -- The multiplier halves sum to less than 2^32, so both accumulators
    -- fit in UInt64 even with the carry and increment halves included.
    low_product ::= low * 1284865837 + 4150755663
    high_product ::= high * 1284865837 + low * 1481765933 + low_product / 4294967296 + 335903614
    next = [high_product % 4294967296] * 4294967296 + low_product % 4294967296
}

_pcg_seed_state(.seed: UInt64) -> (.state: UInt64) := {
    increment: UInt64 = 1442695040888963407
    maximum: UInt64 = 18446744073709551615
    combined :: UInt64 = 0
    if seed > maximum - increment { combined = seed - [maximum - increment] - 1 } else {
        combined = seed + increment
    }
    state = _pcg_advance(.state = combined).next
}

Pcg32 init(.seed: UInt64) -> (.result: Pcg32) := {
    result = (._state = _pcg_seed_state(.seed = seed).state)
}

reseed(.self: $&Pcg32, .seed: UInt64) -> () := {
    self&._state = _pcg_seed_state(.seed = seed).state
}

-- Only the low 32 bits of state >> 27 and the 19 bits of state >> 45
-- participate in the output XOR. Their sum and overlap fit in UInt64.
_pcg_xor_window(.left: UInt64, .right: UInt64) -> (.value: UInt64) := {
    a ::= left
    b ::= right
    place :: UInt64 = 1
    overlap :: UInt64 = 0
    while b != 0 {
        if a % 2 != 0 and b % 2 != 0 { overlap = overlap + place }
        a = a / 2
        b = b / 2
        place = place * 2
    }
    value = left + right - overlap * 2
}

next_uint32(.self: $&Pcg32) -> (.value: UInt32) := {
    previous ::= self&._state
    self&._state = _pcg_advance(.state = previous).next
    mixed ::= _pcg_xor_window(.left = [previous / 134217728] % 4294967296,
        .right = previous / 35184372088832).value
    rotation ::= previous / 576460752303423488
    divisor :: UInt64 = 1
    remaining ::= rotation
    while remaining > 0 { divisor = divisor * 2 remaining = remaining - 1 }
    rotated ::= mixed / divisor + [mixed % divisor] * [4294967296 / divisor]
    value = unwrap_or_abort(.value = UInt32(.value = rotated)).result
}

next_uint64(.self: $&Pcg32) -> (.value: UInt64) := {
    high ::= UInt64(.value = next_uint32(.self = self).value)
    low ::= UInt64(.value = next_uint32(.self = self).value)
    value = high * 4294967296 + low
}

next_bool(.self: $&Pcg32) -> (.value: Bool) := {
    value = next_uint32(.self = self).value >= 2147483648
}

uniform_uint32(.self: $&Pcg32, .upper_bound: UInt32) -> (.result: Errable#(.t: UInt32,
        .reasons : (..invalid_range))) := {
    if upper_bound == 0 { result = ..error(.reason = ..invalid_range) return }
    bound ::= UInt64(.value = upper_bound)
    space: UInt64 = 4294967296
    threshold ::= [space - bound] % bound
    while true {
        candidate ::= UInt64(.value = next_uint32(.self = self).value)
        if candidate >= threshold {
            result = ..ok unwrap_or_abort(.value = UInt32(.value = candidate % bound)).result
            return
        }
    }
}

uniform_uint64(.self: $&Pcg32, .upper_bound: UInt64) -> (.result: Errable#(.t: UInt64,
        .reasons : (..invalid_range))) := {
    if upper_bound == 0 { result = ..error(.reason = ..invalid_range) return }
    maximum: UInt64 = 18446744073709551615
    threshold ::= [maximum % upper_bound + 1] % upper_bound
    while true {
        candidate ::= next_uint64(.self = self).value
        if candidate >= threshold {
            bounded ::= candidate % upper_bound
            result = ..ok bounded
            return
        }
    }
}

-- Accumulating exactly representable binary fractions avoids an integer/float
-- cast dependency and never rounds a unit-interval result upward to one.
_pcg_fraction#(.t: Type: Float)(.sample: UInt64, .bits: UInt32) -> (.value: t) := {
    value = 0.0
    one :: t = 1.0
    half :: t = 0.5
    remaining ::= sample
    count ::= bits
    while count > 0 {
        if remaining % 2 != 0 { value = value + one }
        value = value * half
        remaining = remaining / 2
        count = count - 1
    }
}

next_float16(.self: $&Pcg32) -> (.value: Float16) := {
    value = _pcg_fraction#(.t: Float16)(.sample = UInt64(.value = next_uint32(.self = self).value) / 2097152,

        .bits = 11).value
}
next_float32(.self: $&Pcg32) -> (.value: Float32) := {
    value = _pcg_fraction#(.t: Float32)(.sample = UInt64(.value = next_uint32(.self = self).value) / 256,

        .bits = 24).value
}
next_float64(.self: $&Pcg32) -> (.value: Float64) := {
    value = _pcg_fraction#(.t: Float64)(.sample = next_uint64(.self = self).value / 2048, .bits = 53).value
}
