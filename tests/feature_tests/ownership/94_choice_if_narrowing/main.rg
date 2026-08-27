Choice : Type = (
    ..a Int32
    ..b Int32
)

main() -> (.status_code: Int32) := {
    value :: Choice = ..a 7
    if is(.value = value, .variant = ..a) {
        payload ::= value..a
        status_code = payload - 7
    } else {
        status_code = 1
    }
}
