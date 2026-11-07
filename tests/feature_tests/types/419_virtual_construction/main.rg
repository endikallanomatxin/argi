Readable#(.T: Type): Contract = (
    .read: (.self: &T) -> (.value: Int32) where {}
)

Cell := (.value: Int32)

implement Readable#(Cell) (
    .read = (.self: &Cell) -> (.value: Int32) { value = self&.value }
)

Handle: Type = Virtual#(Readable)

wrap := #(.T: Type) (.source: &T) -> (.result: Handle) {
    result = Handle(source)
}

wrap_as := #(.HandleType: Type) (.source: &Cell) -> (.result: HandleType) {
    result = HandleType(source)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= Virtual#(Allocator)($&GeneralPurposeAllocator(system.page_allocator))
    values ::= unwrap_or_abort(.value = DynamicArray#(Int32)(.capacity = 1))

    cell ::= Cell(.value = 42)
    direct ::= Virtual#(Readable)(&cell)
    alias ::= Handle(.value = &cell)
    generic ::= wrap(&cell).result
    copied ::= Handle(&direct)
    parameterized ::= wrap_as#(Handle)(&cell).result

    if Readable#().read(&alias).value != 42 { status_code = 1 }
    if Readable#().read(&generic).value != 42 { status_code = 2 }
    if Readable#().read(&copied).value != 42 { status_code = 3 }
    if Readable#().read(&parameterized).value != 42 { status_code = 4 }
}
