Counter#(.Provider: Type): Contract = (
    .state: Region#(Provider)
    .get: (.self: &Provider) -> (.result: Int32) where reads(self.state)
)
Cell := (.value: Int32)
implement Deinit#(Cell) (.deinit = (.self: $&Cell) -> () {})
Provider := (.cell: &Cell)
implement Counter#(Provider) (
    .state = region(self.cell.value)
    .get = (.self: &Provider) -> (.result: Int32) { result = self&.cell&.value }
)
Holder := (.counter: Virtual#(Counter))
read_at := (.array: &DynamicArray#(Holder), .index: UIntNative) -> (.result: Int32) {
    selected ::= unwrap_or_abort(.value = get_reference(.self = array, .index = index))
    result = Counter#().get(&selected&.counter)
}
main := (.system: System) -> () {
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= Virtual#(Allocator)($&allocator_provider)
    array ::= unwrap_or_abort(.value = DynamicArray#(Holder)(.capacity = 1))
    cell ::= Cell(42)
    provider: Provider = (.cell = &cell)
    push_assume_capacity(.self = $&array, .value = Holder(Virtual#(Counter)(&provider)))
    deinit(.self = $&cell)
    _ = read_at(&array, 0)
    deinit(.self = $&array)
}
