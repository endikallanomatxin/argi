main() -> (.status_code: Int32) := {
    i :: Int32 = 0
    while 1 == 1 {
        if i == 0 {
            break
        }

        i = i + 1
    }

    status_code = i
}
