main() -> (.status_code: Int32) := {
    value : ?Int32 = ..some(.value = 5)

    if value? {
        payload ::= value..some
        status_code = payload.value - 5
        return
    }

    status_code = 1
}
