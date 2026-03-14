shared := #import("/shared")

main () -> (.status_code: Int32) := {
    status_code = shared.read_shared()
}
