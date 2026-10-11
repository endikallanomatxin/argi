Selection: Type = (..left, ..right)

Permission: Type = (..allow, ..deny)

Selector: Abstract = (
    choose(.self: &Self, .mode: Selection, .permission: Permission, .left: &Int32, .right: &Int32) -> (
        .result : &Int32
    ) where {
        on mode ..left {
            on permission ..allow { depends_on(result, left) }
            on permission ..deny { depends_on(result, right) }
        }
        on mode ..right { depends_on(result, right) }
    }
)

Manager: Type = (.unused: Int32)

Manager implements Selector

choose(
        .self       : &Manager,
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
    manager ::= Manager(0)
    selector ::= to_virtual#(Selector)(&manager)
    live: Int32 = 42
    chosen: &Int32

    {
        local: Int32 = 99
        chosen = choose(&selector, ..left, ..allow, &live, &local)
    }

    if chosen&!= 42 { abort }
}
