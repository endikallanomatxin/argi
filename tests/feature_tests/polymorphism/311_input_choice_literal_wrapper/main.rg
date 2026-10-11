Selection: Type = (..left, ..right)

select_reference(.mode: Selection, .left: &Int32, .right: &Int32) -> (.result: &Int32) := {
    match mode {
        ..left { result = left }
        ..right { result = right }
    }
}

select_left(.left: &Int32, .right: &Int32) -> (.result: &Int32) := {
    result = select_reference(..left, left, right)
}

main() -> () := {
    live: Int32 = 42
    expired: &Int32

    {
        local: Int32 = 99
        expired = &local
    }

    chosen ::= select_left(&live, expired)
    if chosen&!= 42 { abort }
}
