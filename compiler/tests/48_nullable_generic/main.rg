main () -> (.status_code: Int32) := {
    value : Nullable#(.t: Int32) = ..some(.value = 5)

    match value {
        ..none {
            status_code = 1
        }
        ..some(payload) {
            status_code = payload.value - 5
        }
    }
}
