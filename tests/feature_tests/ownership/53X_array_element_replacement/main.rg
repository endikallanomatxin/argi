read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    values :: [4]Int32 = (1, 2, 3, 4)
    pointer := &values[1]
    values[1] = 5
    read(.value = pointer)
    status_code = 0
}
