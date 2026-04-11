MaybeInt : Type = (
    ..none
    ..some Int32
)

main() -> (.status_code: Int32 = 0) := {
    a :: Int32 = 40
    b :: Int32 = 2
    x : MaybeInt = ..some a + b

    if x..some != 42 {
        status_code = 1
    }
}
