Result: Type = (
    ..ok(.value: Int32),
    ..error(.code: UnicodeScalar),
)

main() -> (.status_code: Int32) := {
    value: Result = ..ok
    status_code = 0
}
