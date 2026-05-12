Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..error(.code = 'x')

    if value == ..error {
        if value != ..ok {
            status_code = 0
            return
        }
    }

    status_code = 1
}
