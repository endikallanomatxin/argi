main() -> (.status_code: Int32 = 0) := {
    fallback :: Int32 = 0
    outside :: &Int32 = &fallback
    i :: Int32 = 0
    while i < 1 {
        local ::= i + 1
        outside = &local
        i = i + 1
        continue
    }
    status_code = outside&
}
