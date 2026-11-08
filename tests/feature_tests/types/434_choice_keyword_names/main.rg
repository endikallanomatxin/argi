Command: Type = (..test Int32, ..return, ..if)

Record := (.test: Int32, .return: Int32, .if: Bool)

accept := (.test: Int32) -> (.value: Int32 = 7) {}

main := () -> (.status_code: Int32 = 0) {
    record ::= Record(.test = 41, .return = 2, .if = true)
    record.test = record.test +1
    if record.test != 42 or record.return != 2 or record.if == false { abort }
    if accept(.test = record.test) != 7 { abort }
    command: Command = ..test record.test
    match command {
        ..test value { if value != 42 { abort } }
        ..return { abort }
        ..if { abort }
    }
    selected: Command = ..return
    match selected {
        ..test _ { abort }
        ..return {}
        ..if { abort }
    }
}
