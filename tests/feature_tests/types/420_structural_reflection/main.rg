Pair := (.a: Int32, .b: Int32)

Selection: Type = (..first Int32, ..second Int32)

make_field := #(.T: Type) (.name: StringView, .context: &Int32) -> (.result: T) {
    result = context&
}

make := #(.T: Type) (.context: &Int32) -> (.result: T) {
    collected ::= collect_fields#(T, make_field, Int32)(.context = context)
    if collected[0] != 42 { abort }
    result = construct_record#(T, make_field)(.context = context)
}

_SelectContext := (.calls: $&Int32)

select_second := #(.T: Type) (.name: StringView, .context: &_SelectContext) -> (.ok: Bool) {
    ok = name == "second"
}

build_payload := #(.T: Type) (.name: StringView, .context: &_SelectContext) -> (.result: T) {
    context&.calls&= context&.calls&+ 1
    result = 42
}

exercise := () -> (.value: Int32) {
    n: Int32 = 42
    pair ::= make#(Pair)(&n)
    if pair.a != 42 or pair.b != 42 { abort }
    calls :: Int32 = 0
    context ::= _SelectContext(.calls = $&calls)
    selected ::= construct_choice#(Selection, build_payload, select_second)(.context = &context)
    match selected {
        ..first _ { abort }
        ..second payload { if payload != 42 { abort } }
    }
    if calls != 1 { abort }
    value = pair.a
}

main := () -> (.status_code: Int32 = 0) {
    check_assumptions()
    check_owning()
    if exercise() != 42 { abort }
    #if exercise() != 42 { abort }
}

Owner := (.drops: $&Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { self&.drops&= self&.drops&+ 1 }
)

OwningChoice: Type = (..owner Owner)

select_owner := #(.T: Type) (.name: StringView, .context: $&Int32) -> (.ok: Bool = true) {}

build_owner := #(.T: Type) (.name: StringView, .context: $&Int32) -> (.result: T) {
    result = (.drops = context)
}

check_owning := () -> () {
    drops :: Int32 = 0
    {
        choice ::= construct_choice#(OwningChoice, build_owner, select_owner)(
            .context = $&drops
        )
        if drops != 0 { abort }
    }
    if drops != 1 { abort }
}

shift_field := #(.T: Type) (.name: StringView, .context: &Int32, .offset: Int32) -> (.result: T) {
    result = context&+ offset
}

check_assumptions := () -> () {
    n: Int32 = 40
    assume offset :: Int32 = 2
    pair ::= construct_record#(Pair, shift_field)(.context = &n)
    if pair.a != 42 or pair.b != 42 { abort }
}
