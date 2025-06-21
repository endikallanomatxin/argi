main () -> (Int32) := {
    -- This file tests
    -- constant and variable declarations
    -- combined and separate assignments

    -- Constants
    constant_int_combined : Int32 = 1

    constant_int_separate : Int32
    constant_int_separate = 2

    constant_float_combined : Float32 = 3.14

    constant_float_separate : Float32
    constant_float_separate = 2.718


    -- Variables
    variable_int_combined :: Int32 = 42

    variable_int_separate :: Int32
    variable_int_separate = 100
    variable_int_separate = 0x64

    variable_float_combined :: Float32 = 1.618

    variable_float_separate :: Float32
    variable_float_separate = 3.14159
    variable_float_separate = 2.71828

    return 0
}
