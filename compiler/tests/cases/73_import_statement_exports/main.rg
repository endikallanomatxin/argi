#import("./dep")

main () -> (.status_code: Int32) := {
    imported_status : ImportedStatus = (.code = imported_value)
    status_code = read_status() + imported_status.code
}
