-- Test for pointer declaration, referencing, and dereferencing.
main () -> (.status_code: Int32) := {
    a :: Int32 = 42

    -- Declare a pointer 'p' that points to the address of 'a'.
    p : &Int32 = &a

    -- Dereference 'p' to get the value it points to.
    b :: Int32 = p&

    if b != 42 {
        status_code = 1
        return
    }

    -- Assign a new value through the pointer 'p'.
    p& = 100

    if p& != 100 {
        status_code = 2
        return
    }

    status_code = 0
}
