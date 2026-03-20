main () -> (.status_code: Int32) := {
    i :: Int32 = 5
    sum :: Int32 = 0

    while i > 0 {
        sum = sum + i
        i = i - 1
    }

    status_code = sum - 15
}
