dep := import("./dep")
write := #(.T: Type) (.value: $&T) -> () { value&._hidden = 7 }
main := () -> () { value ::= dep.make() write(.value = $&value) }
