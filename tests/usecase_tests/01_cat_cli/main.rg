main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    assume writer ::= $&system.terminal&.stdout

    argc ::= system.args | length(&_)
    if argc >= 2 {
        first_arg := argument_view_at(system.args, 1)
        if first_arg == "-h" or first_arg == "--help" {
            print(
                "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help."
            )
            return
        }
    }

    if argc < 2 {
        status_code = 1
        return
    }

    i :: UIntNative = 1
    while i < argc {
        path := argument_at(system.args, i)
        text_result ::= read_file(system.file_system, path)
        match text_result {
            ..ok ~payload {
                text ::= ~payload
                view ::= as_view(&text)
                write(writer, view)
                i = i + 1
            }
            ..error ~err {
                match err.reason {
                    ..path_open_failed {
                        print("cat: failed to open file")
                    }
                    ..stream_read_failed {
                        print("cat: failed to read file")
                    }
                    ..stream_close_failed {
                        print("cat: failed to close file")
                    }
                    ..out_of_memory {
                        print("cat: out of memory")
                    }
                }
                status_code = 1
                return
            }
        }
    }
}
