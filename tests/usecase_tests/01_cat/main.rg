-- Transfer binary input through one buffered output stream.
main := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> (.status_code: Int32 = 0) {
    assume error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    stdin ::= $&system.terminal&.stdin
    output ::= $&BufferedWriter($&system.terminal&.stdout, view($&zeroed#([8192]UInt8)()))
    defer {
        Writer#().flush(output) handle error {
            status_code = 1
            report_error(.err = &error, .writer = writer) handle ignored {}
        }
    }

    specs ::= (CliSpec("help", "h", "Show help"),)
    arguments ::= parse_cli(.source = system.args, .specs = view(&specs), .start = 1)!!! {
        status_code = 1
    }

    for option in arguments.options {
        if option.name == "help" {
            write_cli_help(
                .program = "cat"
                .about   = "Concatenate files to standard output. With no files or FILE '-', read standard input."
                .specs   = view(&specs)
                .writer  = output
            )!!! { status_code = 1 }
            return
        }
    }

    if length(&arguments.positionals).count == 0 {
        transfer_stream(stdin, output)!!! { status_code = 1 }
    } else {
        for path in arguments.positionals {
            if path == "-" {
                transfer_stream(stdin, output)!!! { status_code = 1 }
            } else {
                copy_input_file(
                    .path = path, .output = output, .file_system = system.file_system
                )!!! {
                    status_code = 1
                }
            }
        }
    }
}

copy_input_file := #(.Output: Type: Writer#(Output)) (
    .path         : StringView,
    .output       : $&Output,
    .file_system  : $&FileSystem,
    .allocator    : $&PageAllocator,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> !!Void = ..ok Void() {
    assume error_tracer
    assume allocator
    file_reader ::= open_file(.file_system = file_system, .path = path)!! path
    transfer_stream($&file_reader, output)!! path
    close($&file_reader)!! path
}
