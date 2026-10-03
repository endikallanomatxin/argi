Widget : Type = (.value: Int32)

Widget init() -> (.value: Int32) := {
    value = 1
}

main() -> (.status_code: Int32 = 0) := {
    widget ::= Widget()
    status_code = widget.value
}
