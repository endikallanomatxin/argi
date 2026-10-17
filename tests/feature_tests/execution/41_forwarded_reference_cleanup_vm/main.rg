Counter: Type = (.count: Int32 = 0, .calls: Int32 = 0)

Resource: Type = (.counter: $&Counter, .id: Int32)

Args: Type = (.target: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

borrow(.owner: $&Resource) -> (.result: $&Resource) := { result = owner }

forward#(.Value: Type)(.value: Value) -> (.result: Value) := { result = value }

second(.first: $&Resource, .second: $&Resource) -> (.result: $&Resource) := { result = second }

observe(.counter: $&Counter, .owner: $&Resource) -> (.result: $&Resource) := {
    counter&.calls = counter&.calls + 1
    result = owner
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 1)
        target := borrow(.owner = $&owner)
        target&= Resource(.counter = $&counter, .id = 2)
        if counter.count != 1 or target&.id != 2 { abort }
        args: Args = (
            .target = forward#(.Value: $&Resource)(.value = borrow(.owner = $&owner))
        )
        copied := args
        copied.target&= Resource(.counter = $&counter, .id = 3)
        if counter.count != 2 or copied.target&.id != 3 { abort }
        other :: Resource = Resource(.counter = $&counter, .id = 9)
        selected := second(
            .second = copied.target, .first = observe(.counter = $&counter, .owner = $&other)
        )
        selected&= Resource(.counter = $&counter, .id = 4)
        if counter.count != 3 or selected&.id != 4 or other.id != 9 { abort }
    }
    if counter.count != 5 or counter.calls != 1 { abort }
    status_code = 42
}
