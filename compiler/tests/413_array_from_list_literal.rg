-- Arrays constructed from list literals allocate storage and copy elements.
main () -> (.status_code: Int32) := {
    arr :: [3]Int32 = [10, 20, 30]
     -- arr is now an array of three Int32 values: 10, 20, and 30.

    if arr.length != 3 {
        status_code = 1
        return
    }

    first :: Int32 = arr[0]
    if first != 10 {
        status_code = 2
        return
    }

    second :: Int32 = arr[1]
    if second != 20 {
        status_code = 3
        return
    }

    arr[1] = 99
    updated :: Int32 = arr[1]
    if updated != 99 {
        status_code = 4
        return
    }

    status_code = 0
}
