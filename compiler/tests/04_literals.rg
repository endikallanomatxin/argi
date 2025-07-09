main () -> (.status_code: Int32) := {
    -- Int literals in different formats
    a :: Int32
    a = 12
    a = 0x10
    a = 0o10
    a = 0b10

    -- Float literals in different formats
    b ::= 32.0
    b = 1e10

    -- Char literals
    c := 'a'

    -- String literals
    d := "hello world!"

    status_code = 0
}

