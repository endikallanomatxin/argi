Marker : Type = (.value: Int32)

deinit(.self: $&Marker) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Marker = (.value = 1)
    first :: Marker = (.value = 2)
    second :: Marker = (.value = 3)
    deinit(.self = $&first)
    deinit(.self = $&second)
    relocate(.source = $&source, .destination = $&first)
    relocate(.source = $&source, .destination = $&second)
    status_code = 0
}
