-- Link the system zlib library with [[native]] library = "z" in the
-- application's argi.toml. These bindings require zlib 1.2.9 or newer.
_crc32_z(
        .previous : CULong,
        .bytes    : RawPointer#(.t: UInt8),
        .count    : CSize,
    ) -> (
        .checksum : CULong
    ): CFunction(.symbol = "crc32_z")

-- zlib reads this initialized range during the call and does not retain it.
-- No storage is allocated, transferred, initialized, or freed by this wrapper.
-- The result is a 32-bit CRC carried in C's unsigned-long representation.
update_crc32(
        .previous : CULong,
        .source   : &ArrayViewRO#(.t: UInt8),
        .ffi      : $&ForeignFunctionInterface = reach ffi,
    ) -> (
        .checksum : CULong
    ) := {
    assume ffi
    count := length(source)

    if count == 0 {
        checksum = previous
        return
    }

    pointer := data(source)
    raw := raw_pointer#(.t: UInt8)(UIntNative(.value = pointer))
    checksum = _crc32_z(previous, raw, count)
}

crc32(
        .source : &ArrayViewRO#(.t: UInt8),
        .ffi    : $&ForeignFunctionInterface = reach ffi,
    ) -> (
        .checksum : CULong
    ) := {
    assume ffi
    checksum = update_crc32(0, source)
}
