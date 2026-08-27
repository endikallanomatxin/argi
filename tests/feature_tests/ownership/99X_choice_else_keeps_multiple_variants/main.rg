Choice : Type = (
    ..a Int32
    ..b Int32
    ..c Int32
)

main() -> (.status_code: Int32) := {
    value :: Choice = ..b 7
    if is(value, ..a) {
        status_code = 1
    } else {
        payload ::= value..b
        status_code = payload
    }
}
