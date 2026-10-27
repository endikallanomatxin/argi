Box := #(.T: Type: Int) (._value: T)

BoxInitArgs: Type = #(.T: Type: Int) (.value: T = 7)

implement#(.T: Type: Int) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (._value = value) }
)

main := () -> (.status_code: Int32 = 0) {
    byte ::= Box#(UInt8)()
    if byte._value != 7 { abort }
    integer ::= Box#(Int32)()
    if integer._value != 7 { abort }
}
