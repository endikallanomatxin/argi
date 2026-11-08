Box := #(.fallback: ?UInt8) (.value: Int32)

main := () -> () { value ::= Box#(.fallback = ..some(.value = 256))(.value = 0) }
