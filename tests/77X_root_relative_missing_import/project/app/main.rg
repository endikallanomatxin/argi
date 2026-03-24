shared := #import(".../missing_shared")

main () -> (.status_code: Int32) := {
    status_code = shared.read_shared()
}
