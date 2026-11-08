Box := #(.enabled: Bool) (.value: Int32)

main := () -> () { value ::= Box#(.enabled = "yes")(.value = 0) }
