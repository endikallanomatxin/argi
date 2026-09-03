Marker : Type = (.value: Int32)

deinit(.self: $&Marker) -> () := {
}

main(.condition: Bool) -> (.status_code: Int32) := {
    source :: Marker = (.value = 1)
    destination :: Marker = (.value = 2)
    if condition {
        deinit(.self = $&destination)
    }
    relocate(.source = $&source, .destination = $&destination)
    status_code = 0
}
