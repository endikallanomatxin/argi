Record : Type = (.key: Int32, .tag: UIntNative)
Record implements ImplicitlyCopyable
ByKey : Type = ()
ByKey implements OrderPolicy#(.t: Record)
less(.self: &ByKey, .left: Record, .right: Record) -> (.ok: Bool) := { ok = left.key < right.key }
main() -> (.status_code: Int32 = 0) := {
    records : [6]Record = (
        (.key = 3, .tag = 0), (.key = 1, .tag = 1), (.key = 2, .tag = 2),
        (.key = 1, .tag = 3), (.key = 3, .tag = 4), (.key = 2, .tag = 5),
    )
    view ::= array_view(.array = $&records).view
    order ::= ByKey()
    sort(.self = $&view, .order = &order)
    seen : [6]UIntNative = (0, 0, 0, 0, 0, 0)
    index :: UIntNative = 0
    while index < 6 {
        record ::= records[index]
        if record.tag >= 6 { abort }
        seen[record.tag] = seen[record.tag] + 1
        if index > 0 {
            before ::= records[index - 1]
            if before.key > record.key { abort }
        }
        index = index + 1
    }
    index = 0
    while index < 6 {
        if seen[index] != 1 { abort }
        index = index + 1
    }
    words : [5]StringView = ("b", "ab", "a", "", "a")
    word_view ::= array_view(.array = $&words).view
    word_order ::= StringViewOrderPolicy()
    sort(.self = $&word_view, .order = &word_order)
    if words[0] != "" or words[1] != "a" or words[2] != "a" or words[3] != "ab" or words[4] != "b" { abort }
    native : [4]UIntNative = (100, 2, 1, 0)
    native_view ::= array_view(.array = $&native).view
    native_order ::= UIntNativeOrderPolicy()
    sort(.self = $&native_view, .order = &native_order)
    if native[0] != 0 or native[1] != 1 or native[2] != 2 or native[3] != 100 { abort }
}
