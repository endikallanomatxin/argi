-- Transfer binary input through one buffered output stream.
main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    stdin ::= $&system.terminal&.stdin
    output ::= $&BufferedWriter($&system.terminal&.stdout, view($&zeroed#([8192]UInt8)()))
    defer {
        Writer#().flush(output) handle error {
            status_code = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
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
                file_reader ::= open_file(
                    .file_system = system.file_system, .path = path, .mode = ..read
                ) handle error, value {
                    add_context(.context = path, .error_tracer = error.tracer)
                    report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
                    status_code = 1
                    return
                }
                transfer_stream($&file_reader, output) handle error, value {
                    add_context(.context = path, .error_tracer = error.tracer)
                    report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
                    status_code = 1
                    return
                }
                close($&file_reader) handle error, value {
                    add_context(.context = path, .error_tracer = error.tracer)
                    report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
                    status_code = 1
                    return
                }
            }
        }
    }
}
