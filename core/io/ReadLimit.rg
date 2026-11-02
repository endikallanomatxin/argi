ReadLimit#(.Source: Type): Contract = (
    .remaining_bytes : (.self: &Source) -> (.count: UIntNative)
)

remaining := #(.Source: Type: ReadLimit#(Source)) (.self: &Source) -> (.count: UIntNative) {
    count = ReadLimit#(Source).remaining_bytes(.self = self)
}
