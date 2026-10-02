main() -> (.status_code: Int32) := {
    values : Array#(.n = 3, .t: Int32) = (2, 4, 6)
    sum :: Int32 = 0

    for & value in values {
        sum = sum + value&
    }

    if sum != 12 {
        status_code = 1
        return
    }

    for $& value in values {
        value& = value& + 1
    }

    if values[0] != 3 or values[1] != 5 or values[2] != 7 {
        status_code = 2
        return
    }

    status_code = 0
}
