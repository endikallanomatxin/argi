positive(.value: Int32) -> (.ok: Bool) := { ok = value > 0 }

select(.value: Int32) -> () := { #if positive(.value = value) {} }

main() -> () := { select(.value = 1) }
