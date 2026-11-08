Owner := (.text: StringView)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

Box := #(.metadata: Owner) (.value: Int32)

main := () -> () { value ::= Box#(.metadata = (.text = "owned"))(.value = 0) }
