Drain: Abstract = (
    drain(.self: &Self, .storage: $&Allocation, .value: Int32) -> (.result: ?Int32) where {
        on result ..some { retains(storage, value) }
        on result ..none {}
    }
)

main() -> () := {}
