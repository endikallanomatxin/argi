make := #(.T: Type) (.value: T) -> () {
    record ::= (.value = value)
}

main := () -> () { make(42) }
