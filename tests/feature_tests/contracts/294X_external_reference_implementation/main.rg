api := import ("./api")

implement api.Inspect#(&api.Foreign) (
    .inspect = (.value: &api.Foreign) -> (.result: Int32) { result = value&.value }
)

main := () -> () {}
