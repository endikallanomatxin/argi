Marker : Type = (.value: Int32)

deinit(.self: $&Marker) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Marker = (.value = 7)
    destination :: Marker = (.value = 0)
    deinit(.self = $&destination)
    relocate(.source = $&source, .destination = $&destination)
    if destination.value == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
}
