main () -> (.status_code: Int32) := {
    support := #import("_test_support/basic")
    imported_status : support.ImportedStatus = (.code = support.imported_value)
    status_code = support.read_status() + imported_status.code
}
