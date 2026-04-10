main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    while true {
        next ::= read_line()

        if is(.value = next, .variant = ..error) {
            status_code = 1
            return
        }

        match next..ok.value {
            ..end {
                return
            }
            ..ok line {
                if &line.text == "" {
                    return
                } else {
                    line_text ::= as_view(.self = &line.text)
                    print(.value = line_text)
                    print(.value = "\n")
                }
            }
        }
    }
}
