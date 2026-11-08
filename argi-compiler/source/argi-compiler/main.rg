main := (.system: System) -> (.status_code: Int32 = 1) {
    assume allocator := Virtual#(Allocator)($&GeneralPurposeAllocator(system.page_allocator))
    stdout_writer := $&BufferedWriter($&system.terminal&.stdout)
    stderr_writer := $&BufferedWriter($&system.terminal&.stderr)
    assume writer := stderr_writer
    assume error_tracer ::= $&Virtual#(ErrorTracer)($&FixedSizeErrorTracer())

    command ::= ap.parse#(CompilerCommand)(system.args, .start = 1)!!! { status_code = 2 }
    match command {
        ..version _ {
            write(stdout_writer, "argi-compiler (self-hosted CLI prototype)\n")!!!
            status_code = 0
        }
        ..help args {
            ap.write_typed_help#(CompilerCommand)(
                stdout_writer
                &args.arguments
                .program = "argi-compiler"
                .about   = "Self-hosted Argi compiler (CLI prototype)"
            )!!!
            status_code = 0
        }
        ..build args {
            -- Backend will consume args.path.value and build options.
            write(stderr_writer, "build is not implemented yet\n")!!!
        }
        ..check args {
            write(stderr_writer, "check is not implemented yet\n")!!!
        }
        ..run args {
            write(stderr_writer, "run is not implemented yet\n")!!!
        }
        ..repl args {
            write(stderr_writer, "repl is not implemented yet\n")!!!
        }
        ..test args {
            write(stderr_writer, "test is not implemented yet\n")!!!
        }
        ..init args {
            write(stderr_writer, "init is not implemented yet\n")!!!
        }
        ..format args {
            if args.check.value and args.stdout.value {
                write(stderr_writer, "error: --check conflicts with --stdout\n")!!!
                status_code = 2
                return
            }
            write(stderr_writer, "format is not implemented yet\n")!!!
        }
        ..lsp _ {
            write(stderr_writer, "lsp is not implemented yet\n")!!!
        }
    }
}
