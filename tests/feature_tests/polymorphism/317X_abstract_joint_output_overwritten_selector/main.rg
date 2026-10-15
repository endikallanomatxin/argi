Outcome: Type = (..yes, ..no)

Splitter#(.Participant: Type): Contract = (
    .choose: (.self: &Participant, .flag: Bool, .left: &Int32, .right: &Int32) -> (
        .first  : Outcome,
        .second : Outcome,
        .value  : &Int32
    ) where {
        on first ..yes {
            on second ..yes { depends_on(value, left) }
            on second ..no { depends_on(value, right) }
        }
        on first ..no { depends_on(value, right) }
    }
)

Manager: Type = (.unused: Int32)

implement Splitter#(Manager) (.choose = _impl_choose_Manager)

_impl_choose_Manager := (
        .self  : &Manager,
        .flag  : Bool,
        .left  : &Int32,
        .right : &Int32
    ) -> (
        .first  : Outcome,
        .second : Outcome,
        .value  : &Int32
    )  {
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

main() -> () := {
    manager ::= Manager(0)
    splitter ::= to_virtual#(Splitter)(&manager)
    live: Int32 = 42
    values: (.first: Outcome, .second: Outcome, .value: &Int32)

    {
        local: Int32 = 99
        values = choose(&splitter, true, &live, &local)
    }

    values.second = ..yes

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
