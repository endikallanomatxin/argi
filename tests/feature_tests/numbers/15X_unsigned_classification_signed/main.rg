unsigned_identity := #(.T: Type: UInt) (.value: T) -> (.result: T) { result = value }

main := () -> () {
    value :: Int32 = 7
    unsigned_identity(value)
}
