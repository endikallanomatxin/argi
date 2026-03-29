main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    while true {
        next ::= read_line(.allocator = system.allocator)

        if next == ..end {
            return
        }

        line ::= next..ok.text
        if line == "" {
            return
        }

        print(line)
        print("\n")
    }
}
