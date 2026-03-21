main () -> (.status_code: Int32) := {
    sum :: Int32 = 0

    for i in Range(.start = 1, .end = 5, .step = 1) {
        sum = sum + i
    }

    if sum != 10 {
        status_code = 1
        return
    }

    status_code = 0
}
