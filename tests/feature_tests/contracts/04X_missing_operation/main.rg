Readable: Contract = (
    read(.source: &Self) -> (.value: Int32)
)

Cell: Type = (.value: Int32)

Cell satisfies Readable

main() -> () := {}
