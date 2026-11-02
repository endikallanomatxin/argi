Box := #(.t: Type) (.value: ?t)

set_invalid := #(.t: Type) (.self: $&Box#(t)) -> () {
    self&.value = ..missing
}

main := () -> () {
    box :: Box#(Int32) = (.value = ..none)
    set_invalid(.self = $&box)
}
