#if target_os("linux") or target_os("macos") {
_platform_path_is_separator(.byte: UInt8) -> (.ok: Bool) := {
    ok = byte == 47
}

_platform_path_root_length(.view: &StringView) -> (.length: UIntNative = 0) := {
    if view&.length > 0 {
        if bytes_get(.view = view, .index = 0).byte == 47 { length = 1 }
    }
}

}
