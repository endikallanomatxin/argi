main(.system: System = System()) -> (.status_code: Int32) := {
    if length(.self = system.args).count < 2 {
        status_code = 1
        return
    }

    path ::= system.args[1]
    text ::= read_file(.self = system.file_sys, .path = path)
    print(.text = text)
    flush()
    deinit(.self = $&text)
    status_code = 0
}
