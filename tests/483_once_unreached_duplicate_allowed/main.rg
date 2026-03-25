once setup() -> () := {
}

path_a() -> () := {
    setup()
}

path_b() -> () := {
    setup()
}

main() -> (.status_code: Int32) := {
    path_a()
    status_code = 0
}
