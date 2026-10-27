identity := #(.T: Type) (.value: T) -> (.result: T) { result = ~value }

main := () -> () {
    source: Int8 = 7
    value ::= identity#(.Destination: Int64)(source)
}
