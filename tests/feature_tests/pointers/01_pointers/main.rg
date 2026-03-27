-- Test for pointer declaration, referencing, and dereferencing with read/write distinction.
main () -> (.status_code: Int32) := {
    a :: Int32 = 42

    -- Read-only pointer to 'a'.
    ro : &Int32 = &a
    b :: Int32 = ro&

    if b != 42 {
        status_code = 1
        return
    }

    -- Mutable pointer to 'a'.
    rw : $&Int32 = $&a
    rw& = 100

    if rw& != 100 {
        status_code = 2
        return
    }

    if a != 100 {
        status_code = 3
        return
    }

    status_code = 0
}
