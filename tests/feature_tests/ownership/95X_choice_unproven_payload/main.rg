Choice : Type = (
    ..a Int32
    ..b Int32
)

main() -> (.status_code: Int32) := {
    value :: Choice = ..a 7
    payload ::= value..a
    status_code = payload
}
