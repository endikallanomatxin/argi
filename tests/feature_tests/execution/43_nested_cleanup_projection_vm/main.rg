drop_count :: Int32 = 0

Leaf := (.id: Int32)

Pair := (.first: Leaf, .second: Leaf)

Choice: Type = (..none, ..some(.pair: Pair))

Outer := (.before: Leaf, .choice: Choice, .after: Leaf)

implement Deinit#(Leaf) (
    .deinit = (.self: $&Leaf) -> () {
        drop_count = drop_count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    {
        owner :: Outer = (
            .before = Leaf(.id = 1)
            .choice = ..some(.pair = (.first = Leaf(.id = 2), .second = Leaf(.id = 3)))
            .after  = Leaf(.id = 4)
        )
        owner.choice = ..none
        if drop_count != 2 { abort }
        after := $&owner.after
        after&= Leaf(.id = 5)
        if drop_count != 3 { abort }
        taken ::= ~owner.before
        owner.choice = ..some(.pair = (.first = Leaf(.id = 6), .second = Leaf(.id = 7)))
        if drop_count != 3 { abort }
    }
    if drop_count != 7 { abort }
    status_code = 42
}
