Args := (.number: Int32)

read_reached := (.number: Int32) -> (.result: Int32) { result = number }

read := Args -> (.result: Int32) {
    assume number
    result = read_reached()
}

GenericArgs := #(.T: Type) (.number: T)

read_generic := #(.T: Type: ImplicitlyCopyable) GenericArgs#(T) -> (.result: T) {
    assume number
    result = read_reached_generic#(T)()
}

read_reached_generic := #(.T: Type: ImplicitlyCopyable) (.number: T) -> (.result: T) {
    result = number
}

main := () -> (.status_code: Int32 = 0) {
    if read(42) != 42 { status_code = 1 }
    if read_generic#(Int32)(7) != 7 { status_code = 2 }
    known ::= #run () -> (.result: Int32) { result = read(9) }
    if known != 9 { status_code = 3 }
}
