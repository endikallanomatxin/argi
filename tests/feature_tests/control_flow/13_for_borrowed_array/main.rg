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

    status_code = 0
}
