Selection: Type = (..left, ..right)

select_reference := (.mode: Selection, .left: &Int32, .right: &Int32) -> (.result: &Int32) {
    match mode {
        ..left { result = left }
        ..right { result = right }
    }
}

main := () -> () {
    live: Int32 = 42
    expired: &Int32

    {
        local: Int32 = 99
        expired = &local
    }

    chosen ::= select_reference(..right, &live, expired)
    if chosen&!= 42 { abort }
}
