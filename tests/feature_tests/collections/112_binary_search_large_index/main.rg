Repeated : Type = (.count: UIntNative, .value: Int32, .reads: $&UIntNative)
Repeated implements Indexable#(.t: Int32)
length(.self: &Repeated) -> (.count: UIntNative) := { count = self&.count }
get_ro_ref(.self: &Repeated, .index: UIntNative) -> (.result: Errable#(.t: &Int32, .reasons: (..out_of_bounds))) := {
    if index >= self&.count { abort }
    self&.reads& = self&.reads& + 1
    result = ..ok &self&.value
}
main() -> (.status_code: Int32 = 0) := {
    bits ::= size_of(.type = UIntNative) * 8
    count :: UIntNative = 0
    bit :: UIntNative = 0
    while bit < bits {
        count = count * 2 + 1
        bit = bit + 1
    }
    reads :: UIntNative = 0
    collection :: Repeated = (.count = count, .value = 1, .reads = $&reads)
    order ::= Int32OrderPolicy()
    if is(.value = binary_search(.self = &collection, .value = 2, .order = &order).index, .variant = ..some) { abort }
    if reads > bits + 1 { abort }
    reads = 0
    match binary_search(.self = &collection, .value = 1, .order = &order).index {
        ..none { abort }
        ..some found { if found.value != 0 { abort } }
    }
    if reads > bits + 1 { abort }
}
