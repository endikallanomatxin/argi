read(.value: &Int32) -> (.result: Int32) := {
    result = value&
}

write(.value: $&Int32) -> () := {
    value& = 7
}

main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    exclusive := $$&value
    write(.value = exclusive)
    status_code = read(.value = exclusive).result - 7
}
