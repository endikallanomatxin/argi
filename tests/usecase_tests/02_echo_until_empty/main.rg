-- Echo complete lines until an empty line or EOF, including a final line without LF.
main := (.system: System) -> (.status_code: Int32 = 0)  {
    assume writer ::= $&system.terminal&.stderr
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    output ::= $&system.terminal&.stdout
    assume reader ::= $&system.terminal&.stdin
    defer {
        Writer#().flush(output) handle error {
            status_code = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        }
    }

    while true {
        match [read_line()!!! { status_code = 1 }] {
            ..end { break }
            ..ok ~line {
                text ::= view(&line)
                if text == "" { break }

                print(text, .writer = output)!!! { status_code = 1 }
                Writer#().flush(output)!!! { status_code = 1 }
            }
        }
    }
}
