-- Echo complete lines until an empty line or EOF, including a final line without LF.
main(.system: System) -> !Void = ..ok Void() := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    assume writer ::= $&system.terminal&.stdout
    assume reader ::= $&system.terminal&.stdin
    #defer flush(writer)!

    while true {
        match read_line()! {
            ..end { return }
            ..ok ~line {
                text ::= as_view(&line)
                if text == "" { return }

                print(text)!
                flush(writer)!
            }
        }
    }
}
