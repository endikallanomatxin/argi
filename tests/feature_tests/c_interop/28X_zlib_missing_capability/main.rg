zlib := import("codecs/checksum/zlib")
main() -> (.status_code: Int32 = 0) := {
    bytes : [1]UInt8 = (42)
    source := view(&bytes)
    checksum := zlib.crc32(&source)
}
