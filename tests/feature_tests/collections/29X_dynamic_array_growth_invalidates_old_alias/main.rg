main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    first_push ::= push#(.t: Int32)(.self = $&array, .value = 10)
    if is(.value = first_push, .variant = ..error) {
        status_code = 1
        return
    }

    old_alias ::= &array[0]
    second_push ::= push#(.t: Int32)(.self = $&array, .value = 20)
    if is(.value = second_push, .variant = ..error) {
        status_code = 2
        return
    }

    status_code = old_alias&
    deinit#(.t: Int32)(.self = $&array)
}
