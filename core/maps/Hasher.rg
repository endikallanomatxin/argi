-- Hash implementations consume blocks; keys choose their canonical byte stream.
Hasher#(.State: Type): Contract = (
    .write_bytes : (.self: $&State, .bytes: ArrayView#(UInt8)) -> ()
    .finish      : (.self: &State) -> (.hash: UIntNative)
)

-- FNV-1a-64, with explicit offset basis. This is a non-cryptographic hash.
-- https://www.ietf.org/archive/id/draft-eastlake-fnv-25.html
StandardHasher := (._state: UInt64)

implement Init#(StandardHasher) (
    .init = (.seed: UInt64 = 14695981039346656037) -> (.result: StandardHasher) {
        result = (._state = seed)
    }
)

-- Both operands fit the requested low-bit window. Arithmetic XOR avoids
-- introducing a hashing-specific compiler primitive.
-- TODO: Use ordinary bitwise XOR once the language provides it.
_hash_xor_window := (.left: UInt64, .right: UInt64) -> (.result: UInt64) {
    a ::= left
    b ::= right
    place :: UInt64 = 1
    overlap :: UInt64 = 0
    while b != 0 {
        if a % 2 != 0 and b % 2 != 0 { overlap = overlap + place }
        a = a / 2
        b = b / 2
        if b != 0 { place = place * 2 }
    }
    result = left + right - overlap * 2
}

_hash_fnv_byte := (.state: UInt64, .byte: UInt8) -> (.result: UInt64) {
    low_byte ::= state % 256
    digit ::= byte | convert#(.to: UInt64)(_)
    mixed ::= state - low_byte + _hash_xor_window(.left = low_byte, .right = digit).result
    low ::= mixed % 4294967296
    high ::= mixed / 4294967296
    -- Multiply by 0x100000001b3 modulo 2^64 using bounded intermediates.
    low_product ::= low * 435
    high_product ::= high * 435 + low * 256 + low_product / 4294967296
    result = [high_product % 4294967296] * 4294967296 + low_product % 4294967296
}

implement Hasher#(StandardHasher) (
    .write_bytes = (.self: $&StandardHasher, .bytes: ArrayView#(UInt8)) -> () {
        index :: UIntNative = 0
        while index < length(&bytes) {
            byte ::= unwrap_or_abort(.value = get_reference(&bytes, .index = index))
            self&._state = _hash_fnv_byte(.state = self&._state, .byte = byte&)
            index = index + 1
        }
    }
    .finish = (.self: &StandardHasher) -> (.hash: UIntNative) {
        #if target_pointer_bits(64) {
            hash = self&._state | convert#(.to: UIntNative)(_)
        } #else {
            -- Fold into the native width rather than discard the upper bits.
            radix :: UInt64 = 1
            width ::= size_of(.type = UIntNative) * 8
            index :: UIntNative = 0
            while index < width {
                radix = radix * 2
                index = index + 1
            }
            remaining ::= self&._state
            folded :: UInt64 = 0
            while remaining != 0 {
                folded = _hash_xor_window(.left = folded, .right = remaining % radix).result
                remaining = remaining / radix
            }
            hash = unwrap_or_abort(.value = [folded | convert#(.to: UIntNative)(_)])
        }
    }
)
