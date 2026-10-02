Box#(.t: Type) : Type = (.value: t)
Pair#(.a: Type, .b: Type) : Type = (.first: a, .second: b)
inspect#(.a: Type, .b: Type)(.first: a, .second: b) -> (.result: UIntNative) := {
    result = second.value
}
main() -> (.status_code: Int32 = 0) := {
    pair :: Pair#(.a: Box#(.t: Int32), .b: Box#(.t: UIntNative)) = (
        .first = (.value = 7),
        .second = (.value = 9),
    )
    named ::= inspect#(.a: Box#(.t: Int32), .b: Box#(.t: UIntNative))(.first = pair.first, .second = pair.second).result
    positional ::= inspect#(Box#(.t: Int32), Box#(.t: UIntNative))(.first = pair.first, .second = pair.second).result
    if named != 9 or positional != 9 { status_code = 1 }
}
