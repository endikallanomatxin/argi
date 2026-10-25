unrelated(.missing: Int32) -> () := {}

main() -> (.status_code: Int32 = 0) := {
    #if false { missing := 42 }
    status_code = missing
}
