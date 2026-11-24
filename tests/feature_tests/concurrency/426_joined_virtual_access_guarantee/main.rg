Compute#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: UInt32) where {}
)

First := (.marker: UInt8)
Second := (.marker: UInt8)

implement Compute#(&First) (
    .observe = (.receiver: &First) -> (.value: UInt32) { value = 1 }
)
implement Compute#(&Second) (
    .observe = (.receiver: &Second) -> (.value: UInt32) { value = 2 }
)

select := (.first: &First, .second: &Second, .choose_first: Bool) -> (.output: Virtual#(Compute)) {
    if choose_first {
        output = Virtual#(Compute)(first)
    } else {
        output = Virtual#(Compute)(second)
    }
}

Owner := (.view: Virtual#(Compute), .expected: UInt32)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        if self&.view.observe().value != self&.expected { abort }
    }
)

consume := (.owner: Owner) -> () {
    held ::= ~owner
}

main := (.system: System) -> () {
    first ::= First(0)
    second ::= Second(0)
    use_first ::= first.marker == second.marker
    view ::= select(.first = &first, .second = &second, .choose_first = use_first).output
    other_view ::= select(.first = &first, .second = &second, .choose_first = use_first == false).output
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    if view.observe().value != 1 { abort }
    if other_view.observe().value != 2 { abort }
    first_owner: Owner = (.view = view, .expected = 1)
    second_owner: Owner = (.view = other_view, .expected = 2)
    consume(.owner = ~first_owner)
    consume(.owner = ~second_owner)
    recover_ordinary(.owner = $&allocator)
}
