setup := once () -> () {
}

main := () -> (.status_code: Int32) {
    setup()
    status_code = 0
}
