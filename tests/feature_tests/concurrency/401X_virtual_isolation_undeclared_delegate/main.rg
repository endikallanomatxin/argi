Observe#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: Int32) where no_access()
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
main := () -> () {
    cell ::= Cell(0)
    view ::= Virtual#(Observe)(&cell)
    delegate ::= Delegate(view)
    isolated_view ::= Virtual#(IsolatedObserve)(&delegate)
    _ = isolated_view
}
