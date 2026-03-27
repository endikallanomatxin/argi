print_help(.system: &System) -> () := {
    print("usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n")
}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    argc ::= system.args | length(&_) | _.count
    if argc >= 2 {
        first_arg := system.args[1]
        if first_arg == "-h" or first_arg == "--help" {
            print_help(.system = &system)
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
        text ::= read_file(system.file_sys, path)
        print(text)
        deinit(.self = $&text)
        i = i + 1
    }
}
