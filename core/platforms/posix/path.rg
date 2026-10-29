#if target_os("linux") or target_os("macos") {
    _platform_path_is_separator := (.byte: UInt8) -> (.ok: Bool) {
        ok = byte == 47
    }

    _platform_path_root_length := (.view: &StringView) -> (.length: UIntNative = 0) {
        assume error_tracer ::= [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
        if view&._length > 0 {
            if unwrap_or_abort(.value = bytes_get(.view = view, .index = 0)) == 47 {
                length = 1
            }
        }
    }

}
