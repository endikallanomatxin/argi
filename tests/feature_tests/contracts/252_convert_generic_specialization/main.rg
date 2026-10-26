Box := <.T: Type> (.value: T)

Wrapped := <.T: Type> (.value: T)

implement<.T: Type> Convert<Box<T>, Wrapped<T>> (
    .Result  : Type = Wrapped<T>
    .convert = (.value: Box<T>) -> (.result: Result) { result = (.value = ~value.value) }
)

implement Convert<Box<Int32>, Wrapped<Int32>> (
    .Result  : Type = Wrapped<Int32>
    .convert = (.value: Box<Int32>) -> (.result: Result) {
        result = (.value = value.value + 10)
    }
)

main := () -> (.status_code: Int32 = 0) {
    specific ::= Box<Int32>(7) | convert<.to: Wrapped<Int32>>(_)
    generic ::= Box<UInt8>(3) | convert<.to: Wrapped<UInt8>>(_)
    if specific.value != 17 or generic.value != 3 { status_code = 1 }
}
