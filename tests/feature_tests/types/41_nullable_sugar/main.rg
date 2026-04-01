main() -> (.status_code: Int32) := {
    value : ?Int32 = ..some(.value = 5)

    if value? {
        status_code = value - 5
        return
    }

    status_code = 1
}
