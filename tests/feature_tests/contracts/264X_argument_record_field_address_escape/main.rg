Value: Type = (.number: Int32)
field_address := (.args: (.value: &Value)) -> (.result: &Int32) {
    result = &args.value&.number
}
escape := () -> (.result: &Int32) {
    local ::= Value(7)
    result = field_address((.value = &local))
}
main := () -> () { escaped ::= escape() }
