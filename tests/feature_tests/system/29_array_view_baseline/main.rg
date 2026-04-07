main() -> (.status_code: Int32) := {
    raw ::= malloc(.size = 16)
    if cast#(.to: UIntNative)(.value = raw) == 0 {
        status_code = 10
        return
    }

    data : $&Int32 = cast#(.to: $&Int32)(.value = cast#(.to: UIntNative)(.value = raw))
    values ::= array_view#(.t: Int32)(.data = data, .length = 4)

    values[0] = 3
    values[1] = 5
    values[2] = 7
    values[3] = 11

    if values[0] != 3 {
        status_code = 11
        return
    }

    if values[3] != 11 {
        status_code = 12
        return
    }

    status_code = values[1] + values[2]
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = raw)))
}
