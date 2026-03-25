main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    imported_status : dep.ImportedStatus = (.code = dep.imported_value)
    status_code = dep.read_status() + imported_status.code
}
