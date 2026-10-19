Counter: Type = (.count: Int32 = 0)

Leaf: Type = (.id: Int32)

Pair: Type = (.first: Leaf, .second: Leaf)

Choice: Type = (..none, ..some(.pair: Pair))

Outer: Type = (.before: Leaf, .choice: Choice, .after: Leaf)

implement Deinit#(Leaf) (
    .deinit = (.self: $&Leaf, .counter: $&Counter = reach cleanup_counter) -> () {
        counter&.count = counter&.count + 1
    }
)

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    assume cleanup_counter ::= $&counter
    {
        owner :: Outer = (
            .before = Leaf(.id = 1)
            .choice = ..some(.pair = (.first = Leaf(.id = 2), .second = Leaf(.id = 3)))
            .after  = Leaf(.id = 4)
        )
        owner.choice = ..none
        if counter.count != 2 { abort }
        after := $&owner.after
        after&= Leaf(.id = 5)
        if counter.count != 3 { abort }
        taken ::= ~owner.before
        owner.choice = ..some(.pair = (.first = Leaf(.id = 6), .second = Leaf(.id = 7)))
        if counter.count != 3 { abort }
    }
    if counter.count != 7 { abort }
    status_code = 42
}
