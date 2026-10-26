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

Manager: Type = (.unused: Int32)

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

Replacer#(.Participant: Type): Contract = (
    .invalidate_value : (.self: &Participant, .value: $&Int32) -> () where invalidates(value)
)

implement Replacer#(Manager) (.invalidate_value = _impl_replace_Manager)

_impl_replace_Manager := (.self: &Manager, .value: $&Int32) -> () { value&= 0 }

main() -> () := {
    manager ::= Manager(0)
    splitter ::= to_virtual#(Splitter)(&manager)
    replacer ::= to_virtual#(Replacer)(&manager)
    live :: Int32 = 42
    values: Results

    {
        local: Int32 = 99
        values = choose(&splitter, true, &live, &local)
    }

    invalidate_value(&replacer, $&live)

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
