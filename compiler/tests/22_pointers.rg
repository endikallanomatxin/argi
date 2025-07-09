-- Test for pointer declaration, referencing, and dereferencing.
main () -> (.status_code: Int32) := {
    -- 1. Declare an integer variable 'a'.
    a :: Int32 = 42

    -- 2. Declare a pointer 'p' and assign it the address of 'a'.
    p : &Int32 = &a

    status_code = 0
}
