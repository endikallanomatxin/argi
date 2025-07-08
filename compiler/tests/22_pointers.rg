-- Test for pointer declaration, referencing, and dereferencing.
main () -> (.status_code: Int32) := {
    -- 1. Declare an integer variable 'a'.
    a :: Int = 42

    -- 2. Declare a pointer 'p' and assign it the address of 'a'.
    p : &Int = &a

    -- 3. Declare another integer 'b' and assign it the dereferenced value of 'p'.
    b :: Int = p&

    -- 4. Check if 'b' is equal to 42.
    if b == 42 {
        status_code = 0
    } else {
        status_code = b
    }
}
