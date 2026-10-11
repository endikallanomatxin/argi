Drain: Abstract = (
    drain(.self: &Self, .storage: $&Allocation) -> (.result: ?Int32) where {
        on result ..some { empties(storage) }
        on result ..none {}
    }
)

main() -> () := {}
