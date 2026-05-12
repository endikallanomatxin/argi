main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    argc ::= system.args | length(&_)
    if argc >= 2 {
        first_arg := system.args[1]
        if first_arg == "-h" or first_arg == "--help" {
            print(.value = "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n")
            return
        }
    }

    if argc < 2 {
        status_code = 1
        return
    }

    i :: UIntNative = 1
    while i < argc {
        path := system.args[i]
        text_result ::= read_file(system.file_sys, path)
        match text_result {
            ..ok payload {
                text ::= payload
                view ::= as_view(.self = &text)
                print(.value = view)
                i = i + 1
            }
            ..error & err {
                match err&.reason {
                    ..path_open_failed {
                        print(.value = "cat: failed to open file\n")
                    }
                    ..stream_read_failed {
                        print(.value = "cat: failed to read file\n")
                    }
                    ..stream_close_failed {
                        print(.value = "cat: failed to close file\n")
                    }
                    ..out_of_memory {
                        print(.value = "cat: out of memory\n")
                    }
                }
                status_code = 1
                return
            }
        }
    }
}
