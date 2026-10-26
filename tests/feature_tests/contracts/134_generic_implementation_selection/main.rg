Copyable<.Value: Type>: Contract = (
    .Result : Type
    .copy   : (.value: Value) -> (.result: Result)
)

implement<.T: Type> Copyable<T> (
    .Result : Type = T
    .copy   = (.value: T) -> (.result: Result) { result = value }
)

main := () -> (.status_code: Int32 = 0) {
    if Copyable<Int32>.copy(42).result != 42 { abort }
    if Copyable<UInt8>.copy(7).result != 7 { abort }
}
