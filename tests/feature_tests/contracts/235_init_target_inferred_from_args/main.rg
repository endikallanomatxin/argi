Box := #(.T: Type) (.value: T)

BoxInitArgs: Type = #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (.value = value) }
)

main := () -> (.status_code: Int32 = 0) {
    byte :: UInt8 = 42
    inferred ::= Box(.value = byte)
    contextual :: Box#(UInt8) = Box(.value = byte)
    if inferred.value != 42 or contextual.value != 42 { abort }
}
