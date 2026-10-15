zlib := import("codecs/checksum/zlib")
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    bytes : [9]UInt8 = (49, 50, 51, 52, 53, 54, 55, 56, 57)
    source := view(&bytes)
    whole := zlib.crc32(&source)
    if whole != 3421780262 { status_code = 1 }
    first := unwrap_or_abort(.value = slice(.self = &source, .start = 0, .count = 4))
    second := unwrap_or_abort(.value = slice(.self = &source, .start = 4, .count = 5))
    initial := zlib.crc32(&first)
    if zlib.update_crc32(initial, &second) != whole { status_code = 2 }
    empty := unwrap_or_abort(.value = slice(.self = &source, .start = 9, .count = 0))
    if zlib.crc32(&empty) != 0 { status_code = 3 }
    if zlib.update_crc32(whole, &empty) != whole { status_code = 4 }
}
