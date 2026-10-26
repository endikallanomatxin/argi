dep := import ("../32_qualified_comptime_calls/dep")

integer_identity := dep.identity<Int32>
IntegerBox := dep.Box<Int32>

forward := <.T: Type> (.value: T) -> (.result: T) {
    specialized := dep.identity<T>
    result = specialized(.value = value)
}

main := () -> (.status_code: Int32) {
    local := dep.identity<Int32>
    box: IntegerBox = (.value = 42)
    if integer_identity(.value = box.value) != 42 { abort }
    if forward<Int32>(.value = 42) != 42 { abort }
    evaluated ::= #run () -> (.result: Int32) {
        specialized := dep.identity<Int32>
        result = specialized(.value = 42)
    }
    if evaluated != 42 { abort }
    status_code = local(.value = 42)
}
