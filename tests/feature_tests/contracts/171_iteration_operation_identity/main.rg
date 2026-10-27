-- Same-named ordinary functions cannot change the protocol used by for.
has_next := (.value: Int32) -> (.ok: Bool) { ok = false }

next := (.value: Int32) -> (.item: Int32) { item = value }

to_iterator := (.value: Int32) -> (.iterator: Int32) { iterator = value }

sum := #(.T: Type: Iterable#(T)) (.values: &T) -> (.total: Int32 = 0) {
    for item in values { total = total + item }
}

main := () -> (.status_code: Int32 = 0) {
    values: [3]Int32 = (1, 2, 3)
    if sum(&values).total != 6 { status_code = 1 }
    iterator ::= Iterable#().to_iterator(&values).iterator
    if has_next(.self = $&iterator).ok == false { status_code = 2 }
    if next(.self = $&iterator).value != 1 { status_code = 3 }
    if next(.value = 7).item != 7 { status_code = 4 }
}
