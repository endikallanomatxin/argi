main () -> (.status_code: Int32) := {
    values : Array#(.n = 3, .t: Int32) = (4, 5, 6)

    if length(.value = values) != 3 {
        status_code = 1
        return
    }

    second :: Int32 = values[1]
    if second != 5 {
        status_code = 2
        return
    }

    status_code = 0
}
