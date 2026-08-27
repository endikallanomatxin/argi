Choice : Type = (
    ..a Int32
    ..b Int32
)

main() -> (.status_code: Int32) := {
    value :: Choice = ..b 7
    if value == ..b {
        payload ::= value..b
        status_code = payload - 7
    } else {
        status_code = 1
    }

    if value != ..a {
        payload ::= value..b
        status_code = status_code + payload - 7
    }
}
