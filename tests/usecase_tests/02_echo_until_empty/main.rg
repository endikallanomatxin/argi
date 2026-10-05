main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    assume writer ::= $&system.terminal&.stdout
    assume reader ::= $&system.terminal&.stdin

    while true {
        next_line_result ::= read_line()

        match next_line_result {
            ..error _ {
                status_code = 1
                return
            }
            ..ok ~next_line {
                match next_line {
                    ..end {
                        return
                    }
                    ..ok ~line {
                        line_text ::= as_view(&line)
                        if line_text == "" {
                            return
                        } else {
                            print(line_text)
                        }
                    }
                }
            }
        }
    }
}
