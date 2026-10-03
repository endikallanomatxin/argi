Tracked : Type = ()
Tracked deinit(.self: $&Tracked, .count: $&Int32) -> () := { count& = count& + 1 }
main() -> (.status_code: Int32 = 0) := {
    count_storage :: Int32 = 0
    assume count ::= $&count_storage
    if true { tracked ::= Tracked() }
    if count_storage != 1 { status_code = 1 }
}
