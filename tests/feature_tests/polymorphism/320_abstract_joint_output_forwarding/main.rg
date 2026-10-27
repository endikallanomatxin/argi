Outcome: Type = (..yes, ..no)

Results := (
    .first  : Outcome,
    .second : Outcome,
    .value  : &Int32
)

Splitter#(.Participant: Type): Contract = (
    .choose : (.self: &Participant, .flag: Bool, .left: &Int32, .right: &Int32) -> Results where {
        on first ..yes {
            on second ..yes { depends_on(value, left) }
            on second ..no { depends_on(value, right) }
        }
        on first ..no { depends_on(value, right) }
    }
)

Manager := (.unused: Int32)

implement Splitter#(Manager) (.choose = _impl_choose_Manager)

_impl_choose_Manager := (.self: &Manager, .flag: Bool, .left: &Int32, .right: &Int32) -> Results {
    if flag {
        first = ..yes
        second = ..yes
        value = left
    } else {
        first = ..no
        second = ..no
        value = right
    }
}

forward := (.splitter: &Virtual#(Splitter), .flag: Bool, .left: &Int32, .right: &Int32) -> (
    .first: Outcome, .second: Outcome, .value: &Int32
) {
    values ::= choose(splitter, flag, left, right)
    first = values.first
    second = values.second
    value = values.value
}

main := () -> () {
    manager ::= Manager(0)
    splitter ::= to_virtual#(Splitter)(&manager)
    live: Int32 = 42
    values: Results

    {
        local: Int32 = 99
        values = forward(&splitter, true, &live, &local)
    }

    match values.first {
        ..yes {
            match values.second {
                ..yes { if values.value&!= 42 { abort } }
                ..no { abort }
            }
        }
        ..no { abort }
    }
}
