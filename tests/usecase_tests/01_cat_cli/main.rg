-- Copy binary input with bounded working storage and checked stream progress.
main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume reader ::= $&system.terminal&.stdin
    assume writer ::= $&system.terminal&.stdout

    specs ::= (CliSpec("help", "h", "Show help"),)
    arguments ::= parse_cli(
        .source = system.args
        .specs  = view(&specs)
        .start  = 1
    )!

    for option in arguments.options {
        if option.name == "help" {
            write_cli_help(
                .program = "cat"
                .about   = "Concatenate files to standard output. With no files or FILE '-', read standard input."
                .specs   = view(&specs)
            )!
            flush()!
            return
        }
    }

    storage ::= zeroed#([8192]UInt8)()
    buffer ::= view($&storage)

    if length(&arguments.positionals).count == 0 {
        copy_stream(.buffer = buffer)!
    } else {
        for path in arguments.positionals {
            if path == "-" {
                copy_stream(.buffer = buffer)!
            } else {
                file ::= open_read(system.file_system, .path = path)!! path
                assume reader ::= $&file

                copy_stream(.buffer = buffer)!! path
                close($&file)!! path
            }
        }
    }

    flush()!
}
