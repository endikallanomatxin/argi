FakeIterator : Type = (
    .index: UIntNative
)

consume(.it: $&Iterator#(.t: Int32)) -> () := {}

main () -> (.status_code: Int32) := {
    fake :: FakeIterator = (.index = 0)
    consume(.it = $&fake)
    status_code = 0
}
