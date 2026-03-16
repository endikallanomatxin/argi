Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok((.value = 7))
    payload := value..ok
    status_code = payload.value - 7
}
