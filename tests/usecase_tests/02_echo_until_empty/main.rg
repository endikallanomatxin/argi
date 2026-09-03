main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    while true {
        next_line_result ::= read_line()

        match next_line_result {
             ..error _ {
                status_code = 1
                return
            }
             ..ok ~ next_line {
                match next_line {
                    ..end {
                        return
                    }
                    ..ok ~ line {
                        line_text ::= as_view(.self = &line)
                        if line_text == "" {
                            return
                        } else {
                            print(.value = line_text)
                            print(.value = "\n")
                        }
                    }
                }
            }
        }
    }
}
