Selection: Type = (..left, ..right)

Permission: Type = (..allow, ..deny)

select_reference(
        .mode       : Selection,
        .permission : Permission,
        .left       : &Int32,
        .right      : &Int32
    ) -> (
        .result : &Int32
    ) := {
    match mode {
        ..left {
            match permission {
                ..allow { result = left }
                ..deny { result = right }
            }
        }
        ..right { result = right }
    }
}

main() -> () := {
    live: Int32 = 42
    expired: &Int32

    {
        local: Int32 = 99
        expired = &local
    }

    chosen ::= select_reference(..left, ..allow, &live, expired)
    if chosen&!= 42 { abort }
}
