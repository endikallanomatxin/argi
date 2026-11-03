callback := #(.T: Type) (.value: CInt) -> (.result: CInt): CFunction(.export = true) {
    result = value
}
main := () -> () {}
