Kind<.Value: Type>: Contract = (.classify: (.value: Value) -> (.result: Int32))

implement<.T: Type> Kind<T> (
    .classify = (.value: T) -> (.result: Int32) { result = 1 }
)

implement<.T: Type> Kind<&T> (
    .classify = (.value: &T) -> (.result: Int32) { result = 2 }
)

implement<.T: Type> Kind<&Array<2, T>> (
    .classify = (.value: &Array<2, T>) -> (.result: Int32) { result = 3 }
)

main := () -> (.status_code: Int32 = 0) {
    values: Array<2, Int32> = (3, 4)
    if Kind<&Array<2, Int32>>.classify(&values).result != 3 { abort }
}
