borrow := #(.Source: Type: Viewable#(Source)) (.self: Source) -> (
    .view : Viewable#(Source).Result
) {
    view = Viewable#(Source).make_view(.self = self)
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    values :: [2]UInt8 = (65, 66)
    mutable :: MutableArrayView#(UInt8) = borrow($&values)
    pointer ::= unwrap_or_abort(.value = get_mutable_reference($&mutable, .index = 0))
    pointer&= 67
    readonly :: ArrayView#(UInt8) = borrow(&values)
    if unwrap_or_abort(.value = get_reference(&readonly, .index = 0))&!= 67 { abort }
    text ::= unwrap_or_abort(.value = string_from_bytes(.bytes = readonly))
    text_view :: StringView = borrow(&text)
    if text_view != "CB" { abort }
    scalars ::= codepoints(.text = text_view)
    if borrow(&scalars) != "CB" { abort }
    if view(.self = &text).view != "CB" { abort }
    if length(&view(.self = &values).view) != 2 { abort }
}
