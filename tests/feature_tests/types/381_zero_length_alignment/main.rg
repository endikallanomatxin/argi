Record := (.first: Int64, .second: Int64)
Empty: Type = [0]Record
Storage := #(.T: Type, .N: UIntNative) (
    .alignment: [0]T,
    .bytes: [N]UInt8
)

copy_value := #(.T: Type, .N: UIntNative) (.bytes: [N]UInt8) -> (.result: T) {
    storage: Storage#(T, N) = (.alignment = (), .bytes = bytes)
    pointer ::= trusted_reinterpret_reference#(.from: [N]UInt8, .to: T)(.base = &storage.bytes)
    result = pointer&
}

main := () -> () {
    storage: Storage#(Record, 32) = (
        .alignment = (), .bytes = zeroed#([32]UInt8)()
    )
    if alignment_of(.type = Storage#(Record, 32)) < alignment_of(.type = Record) { abort }
    if size_of(.type = Empty) != 0 { abort }
    address ::= &storage.bytes | convert#(.to: UIntNative)(_)
    if address % alignment_of(.type = Record) != 0 { abort }
    local ::= copy_value#(.T: Record, .N = #run () -> (.size: UIntNative) { size = size_of(.type = Storage#(Record, 32)) })(.bytes = storage.bytes)
    if local.first != 0 { abort }
    storage.bytes[0] = 42
    if storage.bytes[0] != 42 { abort }
}
