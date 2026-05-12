main() -> (.status_code: Int32) := {
    i :: Int32 = 0
    sum :: Int32 = 0

    while i < 5 {
        i = i + 1

        if i == 3 {
            continue
        }

        sum = sum + i
    }

    if sum != 12 {
        status_code = 1
        return
    }

    status_code = 0
}
