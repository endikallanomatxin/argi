acquire := once #(.T: Type) (.value: T) -> (.result: T) {
    result = value
}

main := () -> () {
    first ::= acquire#(Int32)(.value = 1)
    second ::= acquire#(Int32)(.value = 2)
}
