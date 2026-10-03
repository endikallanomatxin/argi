dep := import("./dep")
consume(.value: dep.Missing) -> () := {}
main() -> (.status_code: Int32) := {
    consume(.value = 1)
    status_code = 0
}
