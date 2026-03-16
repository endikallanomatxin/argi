Result : Type = (
    ..ok(Int32),
    ..error(Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok
    status_code = 0
}
