main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    point := dep.make_point()
    status_code = point._hidden
}
