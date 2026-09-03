Result : Type = (
    ..ok Int32
    ..error Int32
)

main() -> (.status_code: Int32 = 0) := {
    value :: Result = ..ok 42
    first ::= value..ok
    value = ..error 7
    second ::= value..ok
    status_code = first + second
}
