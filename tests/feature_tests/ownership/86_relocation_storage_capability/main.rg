StorageSlot : Type = (.address: Int32)

deinit(.self: $&StorageSlot) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: StorageSlot = (.address = 1)
    destination :: StorageSlot = (.address = 0)
    deinit(.self = $&destination)
    relocate(.source = $&source, .destination = $&destination)
    status_code = destination.address - 1
}
