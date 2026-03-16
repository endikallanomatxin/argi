Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok
    status_code = 0
}
