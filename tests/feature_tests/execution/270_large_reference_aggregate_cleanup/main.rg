Counter: Type = (.drops: Int32 = 0)

Resource: Type = (.counter: $&Counter, .value: Int32)

LargeReference: Type = (.reference: $&Resource, .padding: [40]Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + 1 }
)

forward_large(.source: $&Resource) -> (.result: LargeReference) := {
    result.reference = source
    result.padding = zeroed#(.t: [40]Int32)()
}

copy_large(.source: LargeReference) -> (.result: LargeReference) := { result = source }

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 1)
        returned ::= forward_large(.source = $&owner)
        copied ::= copy_large(.source = returned)
        copied.reference&= Resource(.counter = $&counter, .value = 42)
        if owner.value != 42 or counter.drops != 1 { abort }
    }
    if counter.drops != 2 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 1)
        returned ::= forward_large(.source = $&owner)
        copied ::= returned
        deinit(.self = copied.reference)
    }
    if counter.drops != 3 { abort }
    status_code = 42
}
