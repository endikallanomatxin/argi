Selection: Type = (..left, ..right)

Selector: Abstract = (
    choose(.self: &Self, .mode: Selection, .left: &Int32, .right: &Int32) -> (.result: &Int32) where {
        on mode ..left { depends_on(result, left) }
        on mode ..right { depends_on(result, right) }
    }
)

Manager: Type = (.unused: Int32)

Manager implements Selector

choose(.self: &Manager, .mode: Selection, .left: &Int32, .right: &Int32) -> (.result: &Int32) := {
    match mode {
        ..left { result = left }
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
        chosen = choose(&selector, ..left, &live, &local)
    }

    if chosen&!= 42 { abort }
}
