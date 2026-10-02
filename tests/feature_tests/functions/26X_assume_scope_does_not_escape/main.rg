take(.number: Int32) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    number :: Int32 = 42
    if true { assume number }
    take()
}
