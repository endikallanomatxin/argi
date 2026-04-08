make_value() -> (.value: Int32) := {
    value = 7
}

computed : Int32 = make_value().value

main() -> (.status_code: Int32) := {
    status_code = computed
}
