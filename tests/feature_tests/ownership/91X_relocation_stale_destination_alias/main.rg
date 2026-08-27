Marker : Type = (.value: Int32)

deinit(.self: $&Marker) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Marker = (.value = 1)
    destination :: Marker = (.value = 2)
    old ::= &destination
    deinit(.self = $&destination)
    relocate(.source = $&source, .destination = $&destination)
    status_code = old&.value
}
