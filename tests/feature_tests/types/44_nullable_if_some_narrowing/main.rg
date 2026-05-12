main() -> (.status_code: Int32) := {
    value : ?Int32 = ..some(.value = 8)
    missing : ?Int32 = ..none

    if value? {
        if value != 8 {
            status_code = 1
            return
        }
    } else {
        status_code = 2
        return
    }

    if missing? {
        status_code = 3
        return
    }

    status_code = 0
}
