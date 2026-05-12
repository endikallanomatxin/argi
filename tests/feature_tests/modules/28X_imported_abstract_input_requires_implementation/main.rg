main() -> (.status_code: Int32) := {
    dep := #import("./dep")

    status_code = dep.use_value(.value = 7).status_code
}
