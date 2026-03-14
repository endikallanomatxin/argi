main () -> (.status_code: Int32) := {
    mid := #import("./mid")
    status_code = mid.read_leaf()
}
