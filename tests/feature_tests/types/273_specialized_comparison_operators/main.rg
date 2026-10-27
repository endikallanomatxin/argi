Box := #(.t: Type) (.value: t)

implement#(.t: Type: ImplicitlyCopyable) ImplicitlyCopyable#(Box#(.t: t)) ()

implement#(.t: Type) Equal#(Box#(.t: t), Box#(.t: t), (.left: Box#(.t: t), .right: Box#(.t: t))) (
    .equal = (.args: (.left: Box#(.t: t), .right: Box#(.t: t))) -> (.ok: Bool) {
        ok = args.left.value == args.right.value
    }
)

same := #(.t: Type) (.left: t, .right: t) -> (.ok: Bool) { ok = left == right }

different := #(.t: Type) (.left: t, .right: t) -> (.ok: Bool) { ok = left != right }

below_three := #(.t: Type) (.value: t) -> (.ok: Bool) { ok = value < 3 }

main := (.system: System) -> (.status_code: Int32 = 0) {
    bytes: [3]UInt8 = (97, 98, 99)
    independent_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    independent ::= view(&independent_storage)
    if same#(.t: StringView)(.left = independent, .right = "abc").ok == false { abort }
    if different#(.t: StringView)(.left = independent, .right = "abc").ok { abort }
    if different#(.t: StringView)(.left = independent, .right = "abd").ok == false { abort }
    a :: Box#(.t: UIntNative) = (.value = 9)
    b :: Box#(.t: UIntNative) = (.value = 9)
    c :: Box#(.t: UIntNative) = (.value = 10)
    if same#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok == false { abort }
    if different#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok { abort }
    if different#(.t: Box#(.t: UIntNative))(.left = a, .right = c).ok == false { abort }
    value :: UIntNative = 2
    if below_three#(.t: UIntNative)(.value = value).ok == false { abort }
    large :: UIntNative = 4
    if below_three#(.t: UIntNative)(.value = large).ok { abort }
}
