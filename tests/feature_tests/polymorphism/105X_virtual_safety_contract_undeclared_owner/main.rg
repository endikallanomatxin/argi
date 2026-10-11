Factory: Abstract = (
    make(.self: &Self) -> (.value: Errable#(Allocation, (..out_of_memory)))
    where depends_on(value, self, error_tracer)
)

Cell: Type = (.allocator: $&Virtual#(Allocator))

Cell implements Factory

make(.self: &Cell) -> (.value: Errable#(Allocation, (..out_of_memory))) := {
    value = allocate(self&.allocator, .size = 1, .alignment = 1)
}

main(.system: System) -> () := {
    backing ::= to_virtual#(Allocator)(system.page_allocator)
    cell ::= Cell($&backing)
    factory ::= to_virtual#(Factory)(&cell)
}
