-- Test for pointer declaration, referencing, and dereferencing.
main () -> (.status_code: Int32) := {
    -- 1. Declare an integer variable 'a'.
    a :: Int32 = 42

    -- 2. Declare a pointer 'p' and assign it the address of 'a'.
    p : &Int32 = &a

    -- 3. Declare another integer 'b' and assign it the dereferenced value of 'p'.
    b :: Int32 = p&

    -- 4. Return the value of 'b' as the status code.
    status_code = b
}
