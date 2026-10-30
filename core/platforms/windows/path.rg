#if target_os("windows") {
    _platform_path_is_separator := (.byte: UInt8) -> (.ok: Bool) {
        ok = byte == 47 or byte == 92
    }

    _platform_path_root_length := (.view: &StringView) -> (.length: UIntNative = 0) {

        if view&._length == 0 { return }
        first ::= unwrap_or_abort(.value = bytes_get(.view = view, .index = 0))
        if _platform_path_is_separator(.byte = first).ok {
            length = 1
            if view&._length >= 2 {
                if _platform_path_is_separator(
                    .byte = unwrap_or_abort(.value = bytes_get(.view = view, .index = 1))
                ).ok {
                    -- A UNC root includes both the server and share components.
                    index :: UIntNative = 2
                    while index < view&._length {
                        if _platform_path_is_separator(
                            .byte = unwrap_or_abort(
                                .value = bytes_get(.view = view, .index = index)
                            )
                        ).ok { break }
                        index = index + 1
                    }
                    if index == 2 or index >= view&._length { return }
                    index = index + 1
                    share_start ::= index
                    while index < view&._length {
                        if _platform_path_is_separator(
                            .byte = unwrap_or_abort(
                                .value = bytes_get(.view = view, .index = index)
                            )
                        ).ok { break }
                        index = index + 1
                    }
                    if index == share_start { return }
                    length = index
                    if index < view&._length { length = index + 1 }
                }
            }
            return
        }
        if view&._length < 3 { return }
        uppercase ::= first >= 65 and first <= 90
        lowercase ::= first >= 97 and first <= 122
        letter ::= uppercase or lowercase
        if letter and unwrap_or_abort(.value = bytes_get(.view = view, .index = 1)) == 58 {
            if _platform_path_is_separator(
                .byte = unwrap_or_abort(.value = bytes_get(.view = view, .index = 2))
            ).ok {
                length = 3
            }
        }
    }

}
