main () -> (.status_code: Int32) := {
    if true {
        #import("./dep")
    }
    status_code = 0
}
