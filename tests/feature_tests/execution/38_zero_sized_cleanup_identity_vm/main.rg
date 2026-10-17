Counter: Type = (.count: Int32 = 0)

Empty: Type = ()

Pair: Type = (.first: Empty, .second: Empty)

Choice: Type = (..none, ..some(.pair: Pair))

implement Deinit#(Empty) (
    .deinit = (.self: $&Empty, .counter: $&Counter = reach cleanup_counter) -> () {
        counter&.count = counter&.count + 1
    }
)

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    assume cleanup_counter ::= $&counter
    {
        pair :: Pair = (.first = (), .second = ())
        deinit(.self = $&pair.first)
        if counter.count != 1 { abort }
    }
    if counter.count != 2 { abort }
    {
        pair :: Pair = (.first = (), .second = ())
        pair.first = Empty()
        if counter.count != 3 { abort }
    }
    if counter.count != 5 { abort }
    {
        value :: Choice = ..none
        value = ..some(.pair = (.first = (), .second = ()))
    }
    if counter.count != 7 { abort }
    status_code = 42
}
