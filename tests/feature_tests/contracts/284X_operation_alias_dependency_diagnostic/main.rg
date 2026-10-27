Required#(.Value: Type): Contract = (
    .perform : (.value: Value) -> (.result: Int32)
)

Consumer#(.Value: Type): Contract = (
    .run : (.value: Value) -> (.result: Int32)
)

forward := #(.Value: Type) (.value: Value) -> (.result: Int32) {
    result = Required#(Value).perform(.value = value)
}

implement Consumer#(Int32) (
    .run = forward
)

main := () -> () {
    result ::= Consumer#(Int32).run(.value = 42)
}
