Source: Abstract = (
    get(.self: &Self) -> (.value: &Int32)
    where depends_on(value, missing)
)

main() -> () := {}
