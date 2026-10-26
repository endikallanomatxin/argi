Source<.Provider: Type>: Contract = (
    .Item  : Type
    .Count : Int
    .read  : (.source: &Provider) -> (.value: Item)
)

Cell := (.value: Int32)

implement Source<Cell> (
    .Item  : Type = Int32
    .Count : Int  = 1
    .read  = (.source: &Cell) -> (.value: Int32) { value = source&.value }
)

read_value := <
    .Item: Type, .Count: Int, .T: Type: Source<.Provider: T, .Item: Item, .Count = Count>
> (.source: &T) -> (.value: Item) {
    value = Source<T>.read(source).value
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(.value = 42)
    if read_value(&cell).value != 42 { abort }
}
