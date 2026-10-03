main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    assume writer ::= $&system.terminal&.stdout

    argc ::= system.args | length(&_)
    if argc >= 2 {
        first_arg := argument_view_at(.self = system.args, .index = 1)
        if first_arg == "-h" or first_arg == "--help" {
            print(.value = "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.")
            return
        }
    }

    if argc < 2 {
        status_code = 1
        return
    }

    i :: UIntNative = 1
    while i < argc {
        path := argument_at(.self = system.args, .index = i)
        text_result ::= read_file(system.file_sys, path)
        match text_result {
            ..ok ~ payload {
                text ::= ~payload
                view ::= as_view(.self = &text)
                write(.self = writer, .text = view)
                i = i + 1
            }
            ..error ~ err {
                match err.reason {
                    ..path_open_failed {
                        print(.value = "cat: failed to open file")
                    }
                    ..stream_read_failed {
                        print(.value = "cat: failed to read file")
                    }
                    ..stream_close_failed {
                        print(.value = "cat: failed to close file")
                    }
                    ..out_of_memory {
                        print(.value = "cat: out of memory")
                    }
                }
                status_code = 1
                return
            }
        }
    }
}
