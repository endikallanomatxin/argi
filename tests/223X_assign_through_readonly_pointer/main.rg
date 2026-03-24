-- Negative test: assigning through a read-only pointer must fail
main () -> (.status_code: Int32) := {
    value :: Int32 = 0
    reader : &Int32 = &value
    reader& = 1
    status_code = 0
}
