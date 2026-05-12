Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

consume_ptr(.ptr: &Resource) -> (.status_code: Int32) := {
    status_code = 0
}

main() -> (.status_code: Int32) := {
    resource := Resource()
    first_ptr : &Resource = &resource
    second_ptr : &Resource = first_ptr

    status_code = consume_ptr(.ptr = second_ptr).status_code
}
