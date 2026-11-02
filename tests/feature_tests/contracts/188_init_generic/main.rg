Box := #(.T: Type) (._value: T)

BoxInitArgs: Type = #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (._value = value) }
)

make_box := #(.T: Type) (.value: T) -> (.box: Box#(T)) {
    box = Box#(T)(.value = value)
}

main := () -> (.status_code: Int32 = 0) {
    box ::= make_box(.value = 42)
    if box._value != 42 { abort }
    other ::= Box#(UInt8)(.value = 7)
    if other._value != 7 { abort }
}
