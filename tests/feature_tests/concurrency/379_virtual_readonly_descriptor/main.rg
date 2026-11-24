Counter#(.T: Type): Contract = (
    .increment: (.receiver: $&T, .amount: Int32) -> () where writes(receiver)
)
Cell := (.value: Int32)
implement Counter#(Cell) (
    .increment = (.receiver: $&Cell, .amount: Int32) -> () {
        receiver&.value = receiver&.value + amount
    }
)
Wrapper := (.counter: Virtual#(Counter))

advance := (.wrapper: &Wrapper) -> () {
    counter ::= wrapper&.counter
    wrapper&.counter.increment(1)
    Counter#().increment(.receiver = &counter, .amount = 1)
}

advance_generic := #(.T: Type) (.wrapper: &T) -> () {
    wrapper&.counter.increment(1)
}

main := () -> () {
    cell ::= Cell(40)
    wrapper ::= Wrapper(Virtual#(Counter)($&cell))
    advance(&wrapper)
    advance_generic(&wrapper)
    if cell.value != 43 { abort }
}
