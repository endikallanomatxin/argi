Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), (.value: T)) (
    .Result : Type = Box#(T)
    .init   = (.args: (.value: T)) -> (.result: Result) { result = (.value = args.value) }
)

wrap := #(.T: Type) (.value: T) -> (.result: Box#(T)) {
    result = Box(.value = value)
}

main := () -> (.status_code: Int32 = 0) {
    byte :: UInt8 = 42
    boxed ::= wrap(.value = byte)
    if boxed.value != 42 { abort }
}
