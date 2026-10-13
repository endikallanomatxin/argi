Owner: Type = (.value: Int32)
Owner deinit(.self: $&Owner) -> () := {}
implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})
main := () -> () {}
