Readable: contract = (
    read(.source: &Self) -> (.value: Int32) where {}
)

Cell: Type = (.value: Int32)

Cell satisfies Readable

read(.source: &Cell) -> (.value: Int32) := { value = source&.value }

read(.source: &Cell) -> (.value: Float64) := { value = 2.5 }

-- Conformance must reject ambiguous input dispatch even without a call.
main() -> () := {}
