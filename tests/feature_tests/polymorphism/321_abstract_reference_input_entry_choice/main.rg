Selection: Type = (..left, ..right)

Selector<.Participant: Type>: Contract = (
    .choose : (.self: &Participant, .mode: &Selection, .left: &Int32, .right: &Int32) -> (
        .result : &Int32
    ) where {
        on mode ..left { depends_on(result, left) }
        on mode ..right { depends_on(result, right) }
    }
)

Manager := (.unused: Int32)

implement Selector<Manager> (.choose = _impl_choose_Manager)

_impl_choose_Manager := (.self: &Manager, .mode: &Selection, .left: &Int32, .right: &Int32) -> (
    .result : &Int32
) {
    match mode&{
        ..left { result = left }
        ..right { result = right }
    }
}

main := () -> () {
    manager ::= Manager(0)
    selector ::= to_virtual<Selector>(&manager)
    live: Int32 = 42
    mode :: Selection = ..left
    chosen: &Int32

    {
        local: Int32 = 99
        chosen = choose(&selector, &mode, &live, &local)
    }

    mode = ..right

    if chosen&!= 42 { abort }
}
