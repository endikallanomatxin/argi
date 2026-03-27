is_help_flag(.arg: &StringView) -> (.ok: Bool) := {
    if arg&.length == 2 {
        if bytes_get(.view = arg, .index = 0).byte == 45 {
            if bytes_get(.view = arg, .index = 1).byte == 104 {
                ok = 1 == 1
                return
            }
        }
    }

    if arg&.length == 6 {
        if bytes_get(.view = arg, .index = 0).byte == 45 {
            if bytes_get(.view = arg, .index = 1).byte == 45 {
                if bytes_get(.view = arg, .index = 2).byte == 104 {
                    if bytes_get(.view = arg, .index = 3).byte == 101 {
                        if bytes_get(.view = arg, .index = 4).byte == 108 {
                            if bytes_get(.view = arg, .index = 5).byte == 112 {
                                ok = 1 == 1
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    ok = 1 == 0
}

print_help(.system: &System) -> () := {
    buffer ::= TextBuffer(.allocator = system&.allocator, .capacity = 128)
    push_c_string(.self = $&buffer, .text = "usage: <program> <file> [file...]\n")
    push_c_string(.self = $&buffer, .text = "Concatenate files to standard output.\n")
    push_c_string(.self = $&buffer, .text = "  -h, --help  Show this help.\n")
    print_text_buffer(.buffer = &buffer)
    flush()
    deinit(.self = $&buffer)
}
