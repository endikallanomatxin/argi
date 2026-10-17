Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

choose(.left: $&Resource, .right: $&Resource, .use_left: &Bool) -> (.result: $&Resource) := {
    if use_left&{ result = left } else { result = right }
}

main() -> () := {
    counter :: Counter = Counter()
    left :: Resource = Resource(.counter = $&counter)
    right :: Resource = Resource(.counter = $&counter)
    enabled ::= true
    target := choose(.left = $&left, .right = $&right, .use_left = &enabled)
    target&= Resource(.counter = $&counter)
}
