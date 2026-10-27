Box := #(.T: Type: Int) (._value: T)

implement#(.T: Type: Int) Init#(Box#(T)) (
    .init = (.value: T = 7) -> (.result: Box#(T)) { result = (._value = value) }
)

main := () -> (.status_code: Int32 = 0) {
    byte ::= Box#(UInt8)()
    if byte._value != 7 { abort }
    integer ::= Box#(Int32)()
    if integer._value != 7 { abort }
}
