foreign_cleanup(.value: CInt) -> (): CFunction(.symbol = "foreign_cleanup") where { no_access() }

Owner := (.value: CInt, .ffi: $&ForeignFunctionInterface)
Wrapper := (.owner: Owner)
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        foreign_cleanup(.value = self&.value, .ffi = self&.ffi)
    }
)
Run#(.R: Type): Contract = (
    .run: (.receiver: R, .ffi: $&ForeignFunctionInterface) -> () where {
        no_access()
        isolated()
    }
)
Cell := (.value: CInt)
implement Run#(&Cell) (
    .run = (.receiver: &Cell, .ffi: $&ForeignFunctionInterface) -> () {
        wrapper: Wrapper = (.owner = (.value = 42, .ffi = ffi))
    }
)
main := () -> () {
    cell: Cell = (.value = 0)
    view ::= Virtual#(Run)(&cell)
    _ = view
}
