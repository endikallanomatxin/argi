main () -> (.status_code: Int32) := {
    sum :: Int32 = 0

    for i in Range(.end = 7, .step = 2) {
        sum = sum + i
    }

    if sum != 12 {
        status_code = 1
        return
    }

    status_code = 0
}
