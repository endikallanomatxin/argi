main () -> (.status_code: Int32) := {
    ascending :: Int32 = 0
    descending :: Int32 = 0

    for i in Range(.start = 0, .end = 7, .step = 2) {
        ascending = ascending + i
    }

    for i in Range(.start = 5, .end = 0, .step = -2) {
        descending = descending + i
    }

    if ascending != 12 {
        status_code = 1
        return
    }

    if descending != 9 {
        status_code = 2
        return
    }

    status_code = 0
}
