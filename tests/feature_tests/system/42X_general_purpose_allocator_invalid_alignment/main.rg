main() -> (.status_code: Int32) := {
    allocator ::= GeneralPurposeAllocator()
    attempt ::= allocate(.self = $&allocator, .size = 1, .alignment = 3)
    status_code = 0
}
