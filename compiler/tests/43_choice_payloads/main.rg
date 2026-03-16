Result : Type = (
    ..ok(Int32),
    ..error(Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok(7)
    payload : Int32 = value..ok
    status_code = payload - 7
}
