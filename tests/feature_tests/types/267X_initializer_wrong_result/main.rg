Widget : Type = (.value: Int32)

init(.p: $&Widget) -> (.value: Int32) := {
    p& = (.value = 1)
    value = 1
}

main() -> (.status_code: Int32 = 0) := {
    widget ::= Widget()
    status_code = widget.value
}
