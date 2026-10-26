Kind<.Value: Type>: Contract = (
    .classify : (.value: Value) -> (.result: Int32)
)

implement<.T: Type> Kind<T> (
    .classify = (.value: T) -> (.result: Int32) { result = 1 }
)

implement<.T: Type> Kind<&T> (
    .classify = (.value: &T) -> (.result: Int32) { result = 2 }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= 7
    if Kind<Int32>.classify(7).result != 1 { abort }
    if Kind<&Int32>.classify(&value).result != 2 { abort }
}
