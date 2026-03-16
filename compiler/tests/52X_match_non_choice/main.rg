main () -> (.status_code: Int32) := {
    value : Int32 = 42

    match value {
        ..some(payload) {
            status_code = payload.value
        }
    }
}
