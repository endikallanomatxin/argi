dep := #import("./dep")

main() -> (.status_code: Int32) := {
    _ ::= dep.pick(.value = 1)
    status_code = 0
}
