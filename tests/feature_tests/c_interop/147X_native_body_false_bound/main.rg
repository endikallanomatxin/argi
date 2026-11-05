native_write(.value: $&Int32) -> (): CFunction where { no_access() } := { value& = 42 }
main := () -> () {
    value :: Int32 = 7
    native_write(.value = $&value)
}
