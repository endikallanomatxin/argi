main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    while true {
        next ::= read_line(.allocator = system.allocator)
        should_stop :: Bool = false

        match next {
            ..end {
                should_stop = true
            }
            ..ok(line) {
                if &line.text == "" {
                    should_stop = true
                } else {
                    print(&line.text + "\n")
                }
            }
        }

        if should_stop {
            break
        }
    }
}
