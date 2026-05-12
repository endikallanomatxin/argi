Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..error(.code = 'x')

    if value | is(_, ..error) {
        if is(value, ..error) {
            status_code = 0
        } else {
            status_code = 2
        }
    } else {
        status_code = 1
    }
}
