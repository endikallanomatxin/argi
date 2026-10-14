CollectionLength#(.Collection: Type): Contract = (
    .measure_length: (.self: &Collection) -> (.count: UIntNative)
)
CollectionCapacity#(.Collection: Type): Contract = (
    .measure_capacity: (.self: &Collection) -> (.count: UIntNative)
)

length#(.Collection: Type: CollectionLength#(Collection)) := (.self: &Collection) -> (.count: UIntNative) {
    count = CollectionLength#(Collection).measure_length(.self = self)
}
capacity#(.Collection: Type: CollectionCapacity#(Collection)) := (.self: &Collection) -> (.count: UIntNative) {
    count = CollectionCapacity#(Collection).measure_capacity(.self = self)
}
