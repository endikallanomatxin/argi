main () -> (.status_code: Int32) := {
    start :: Int64 = 1
    finish :: Int64 = 7
    step :: Int64 = 2
    sum :: Int64 = 0

    for i in Range(.start = start, .end = finish, .step = step) {
        sum = sum + i
    }

    if sum != 9 {
        status_code = 1
        return
    }

    status_code = 0
}
