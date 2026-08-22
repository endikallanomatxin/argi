consume(.value: $$&Int32) -> () := {}

main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    mutable := $&value
    consume(.value = mutable)
    status_code = 0
}
