main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    while true {
        next ::= read_line()

        match next {
            ..end {
                return
            }
            ..ok(line) {
                if &line.text == "" {
                    return
                } else {
                    print(&line.text + "\n")
                }
            }
        }
    }
}
