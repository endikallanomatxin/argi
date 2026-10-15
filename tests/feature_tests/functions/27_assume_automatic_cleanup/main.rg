CleanupCount: Type = (.value: Int32)
Tracked : Type = ()
implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked, .count: $&CleanupCount = reach count) -> () {
        count&.value = count&.value + 1
    }
)
main() -> (.status_code: Int32 = 0) := {
    count_storage ::= CleanupCount(.value = 0)
    assume count ::= $&count_storage
    if true { tracked ::= Tracked() }
    if count_storage.value != 1 { status_code = 1 }
}
