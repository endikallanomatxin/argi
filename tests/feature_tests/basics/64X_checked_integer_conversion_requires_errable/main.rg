main := () -> (.status_code: Int32) {

    wide: Int64 = 1
    small: Int8 = wide | convert#(.to: Int8)(_)
    status_code = 0
}
