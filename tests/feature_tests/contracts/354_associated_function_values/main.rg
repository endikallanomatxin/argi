identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

Selector#(.T: Type): Contract = (
    .Chosen: Function
    .select: _
)

implement Selector#(Int32) (
    .Chosen: Function = identity#(Int32)
    .select = identity#(Int32)
)

main := () -> () {
    value: result_of#(Selector#(Int32).Chosen) = select(42)
    if value != 42 { abort }
}
