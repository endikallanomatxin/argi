Buffer : Type = (
    .data: $&UInt8
)

allocate() -> (.data: $&UInt8) #returns_fresh(data) #raw_boundary := {
    address :: UIntNative = 1
    data = cast#(.to: $&UInt8)(.value = address)
}

init(.p: $&Buffer) -> () #trusted_temporal := {
    p& = (.data = allocate().data)
}

release(.self: $&Buffer) -> () #invalidates_dependency(self, data) := {}

read(.value: &UInt8) -> () := {}

main() -> (.status_code: Int32) := {
    buffer :: Buffer = Buffer()
    pointer : &UInt8 = buffer.data
    release(.self = $&buffer)
    read(.value = pointer)
    status_code = 0
}
