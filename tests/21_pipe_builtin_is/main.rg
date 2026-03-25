Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..error(.code = 'x')

    if value | is(.value = _, .variant = ..error) {
        status_code = 0
    } else {
        status_code = 1
    }
}
