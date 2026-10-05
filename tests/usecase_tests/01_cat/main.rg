-- Transfer binary input through one buffered output stream.
main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    stdin ::= $&system.terminal&.stdin
    assume writer ::= $&BufferedWriter(
        $&system.terminal&.stdout
        view($&zeroed#([8192]UInt8)())
    )
    #defer flush(writer)!

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
            return
        }
    }

    if length(&arguments.positionals).count == 0 {
        transfer_stream(stdin, writer)!
    } else {
        for path in arguments.positionals {
            if path == "-" {
                transfer_stream(stdin, writer)!
            } else {
                file_reader ::= open_read(system.file_system, path)!! path
                transfer_stream($&file_reader, writer)!! path
                close($&file_reader)!! path
            }
        }
    }
}
