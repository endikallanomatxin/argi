Large: Type = (.reference: &Int32, .values: [128]Int32)

drops :: Int32 = 0

Large deinit(.self: $&Large) -> () := {
    if self&.reference&!= 31 { abort }
    drops = drops + 1
}

make(.reference: &Int32) -> (.result: Large) := {
    result = Large(reference, zeroed#([128]Int32)())
}

relay(.reference: &Int32) -> (.result: Large) := {
    result = make(reference)
}

main() -> (.status_code: Int32 = 0) := {
    local ::= 31

    {
        value ::= relay(&local)
        if value.reference&!= 31 or value.values[127] != 0 or drops != 0 {
            status_code = 1
            return
        }
    }

    if drops != 1 { status_code = 2 }
}
