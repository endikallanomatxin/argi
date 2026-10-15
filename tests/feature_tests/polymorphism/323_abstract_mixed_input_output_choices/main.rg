Outcome: Type = (..yes, ..no)

Selection: Type = (..left, ..right)

Splitter#(.Participant: Type): Contract = (
    .choose: (.self: &Participant, .mode: Selection, .left: &Int32, .right: &Int32) -> (
        .first  : Outcome,
        .second : Outcome,
        .value  : &Int32
    ) where {
        on mode ..left {
            on first ..yes { depends_on(value, left) }
        }
        on mode ..right { depends_on(value, right) }
    }
)

Manager: Type = (.unused: Int32)

implement Splitter#(Manager) (.choose = _impl_choose_Manager)

_impl_choose_Manager := (
        .self  : &Manager,
        .mode  : Selection,
        .left  : &Int32,
        .right : &Int32
    ) -> (
        .first  : Outcome,
        .second : Outcome,
        .value  : &Int32
    )  {
    match mode {
        ..left {
            first = ..yes
            second = ..yes
            value = left
        }
        ..right {
            first = ..no
            second = ..no
            value = right
        }
    }
}

main() -> () := {
    manager ::= Manager(0)
    splitter ::= to_virtual#(Splitter)(&manager)
    live: Int32 = 42
    values: (.first: Outcome, .second: Outcome, .value: &Int32)

    {
        local: Int32 = 99
        values = choose(&splitter, ..left, &live, &local)
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
