once setup() -> () := {
}

main() -> (.status_code: Int32) := {
    if 1 == 1 {
        setup()
    } else {
        setup()
    }
    status_code = 0
}
