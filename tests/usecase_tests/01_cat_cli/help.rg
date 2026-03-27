is_help_flag(.arg: &StringView) -> (.ok: Bool) := {
    if equals(.left = arg, .right = "-h").ok {
        ok = true
        return
    }

    ok = equals(.left = arg, .right = "--help").ok
}

print_help(.system: &System) -> () := {
    print("usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n")
}
