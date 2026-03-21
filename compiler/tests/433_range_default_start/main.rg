main () -> (.status_code: Int32) := {
    sum :: Int32 = 0

    for i in Range(.end = 4) {
        sum = sum + i
    }

    if sum != 6 {
        status_code = 1
        return
    }

    status_code = 0
}
