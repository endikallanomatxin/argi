Tracked := (.counter: $&Int32, .weight: Int32)
implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.counter& = self&.counter& + self&.weight
    }
)
Pair := (.first: Tracked, .second: Tracked)
Indirect := (.reference: $&Tracked, .sibling: Tracked)
take := (.source: $&Tracked) -> (.result: Tracked) { result = ~source& }
take_first := (.source: $&Pair) -> (.result: Tracked) { result = ~source&.first }
take_through_field := (.source: &Indirect) -> (.result: Tracked) { result = ~source&.reference& }
main := () -> (.status_code: Int32 = 0) {
    counter :: Int32 = 0
    {
        source ::= Tracked(.counter = $&counter, .weight = 100)
        moved ::= take(.source = $&source)
    }
    if counter != 100 { abort }
    {
        pair: Pair = (
            .first = Tracked(.counter = $&counter, .weight = 1)
            .second = Tracked(.counter = $&counter, .weight = 10)
        )
        moved ::= take_first(.source = $&pair)
        if pair.second.weight != 10 { abort }
    }
    if counter != 111 { abort }
    {
        source ::= Tracked(.counter = $&counter, .weight = 1000)
        indirect: Indirect = (
            .reference = $&source
            .sibling = Tracked(.counter = $&counter, .weight = 10000)
        )
        moved ::= take_through_field(.source = &indirect)
        if indirect.sibling.weight != 10000 { abort }
    }
    if counter != 11111 { abort }
}
