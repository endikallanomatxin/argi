main() -> (.status_code: Int32) := {
    reference :: $&Int32
    [$&reference]&= reference
    status_code = 42
}
