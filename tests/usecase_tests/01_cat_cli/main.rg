main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    if system.args | length(&_) < 2 {
        status_code = 1
        return
    }

    path := system.args[1]
    text := read_file(system.file_sys, path)
    print(.value = text)
    status_code = 0
}
