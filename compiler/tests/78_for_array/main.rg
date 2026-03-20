main () -> (.status_code: Int32) := {
    values : Array#(.n = 4, .t: Int32) = (1, 2, 3, 4)
    array_sum :: Int32 = 0

    for value in values {
        array_sum = array_sum + value
    }

    if array_sum != 10 {
        status_code = 1
        return
    }

    status_code = 0
}
