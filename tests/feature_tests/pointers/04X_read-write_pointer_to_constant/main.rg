-- Negative test: taking a read/write pointer to an immutable binding must fail
main () -> (.status_code: Int32) := {
    value : Int32 = 1
    mutable_view : $&Int32 = $&value
    status_code = 0
}
