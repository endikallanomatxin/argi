take(.number: Int32) -> () := {}
child() -> () := { take() }
main() -> (.status_code: Int32 = 0) := {
    assume number :: Int32 = 42
    child()
}
