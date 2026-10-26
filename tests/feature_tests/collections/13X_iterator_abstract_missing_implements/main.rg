FakeIterator := (
    .index : UIntNative
)

consume := <.T: Type: Iterator<T>> (.it: $&T) -> () {}

main := () -> (.status_code: Int32) {
    fake :: FakeIterator = (.index = 0)
    consume(.it = $&fake)
    status_code = 0
}
