main() -> (.status_code: Int32 = 0) := {
    fallback :: Int32 = 0
    outside :: &Int32 = &fallback
    while 1 == 1 {
        local ::= 1
        outside = &local
        break
    }
    status_code = outside&
}
