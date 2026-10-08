Source: Abstract = (
    get(.self: &Self) -> (.result: ?Int32) where {
        on missing ..some {}
    }
)

main() -> () := {}
