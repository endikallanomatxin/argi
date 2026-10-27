Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T)) (
    .init = (.value: T) -> (.result: Box#(T)) { result = (.value = value) }
)

wrap := #(.T: Type) (.value: T) -> (.result: Box#(T)) {
    result = Box(.value = value)
}

main := () -> (.status_code: Int32 = 0) {
    byte :: UInt8 = 42
    boxed ::= wrap(.value = byte)
    if boxed.value != 42 { abort }
}
