main() -> (.status_code: Int32) := {
    values: [2](.left: Int32, .right: Int32) = ((.left = 20), (.left = 22))
    status_code = values[0].left
}
