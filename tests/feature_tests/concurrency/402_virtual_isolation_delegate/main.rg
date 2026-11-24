Observe#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: Int32) where { no_access() isolated() }
)
IsolatedObserve#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: Int32) where {
        reads(receiver)
        isolated()
    }
)
Cell := (.marker: UInt8)
Delegate := (.view: Virtual#(Observe))
implement Observe#(&Cell) (
    .observe = (.receiver: &Cell) -> (.value: Int32) { value = 42 }
)
implement IsolatedObserve#(&Delegate) (
    .observe = (.receiver: &Delegate) -> (.value: Int32) {
        value = receiver&.view.observe().value
    }
)
worker := (.view: Virtual#(IsolatedObserve)) -> (.value: Int32) {
    value = view.observe().value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= Cell(0)
    view ::= Virtual#(Observe)(&cell)
    delegate ::= Delegate(view)
    isolated_view ::= Virtual#(IsolatedObserve)(&delegate)
    future ::= unwrap_or_abort(async#(worker)(.args = (.view = isolated_view)))
    if unwrap_or_abort(await($&future)) != 42 { abort }
}
