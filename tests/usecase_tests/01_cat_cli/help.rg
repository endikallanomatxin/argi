is_help_flag(.arg: &StringView) -> (.ok: Bool) := {
    if arg == "-h" {
        ok = true
        return
    }

    ok = arg == "--help"
}

print_help(.system: &System) -> () := {
    print("usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n")
}
