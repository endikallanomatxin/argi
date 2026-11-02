drop_count :: Int32 = 0

Empty: Type = ()

Pair := (.first: Empty, .second: Empty)

Choice: Type = (..none, ..some(.pair: Pair))

implement Deinit#(Empty) (
    .deinit = (.self: $&Empty) -> () {
        drop_count = drop_count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    {
        pair :: Pair = (.first = (), .second = ())
        deinit(.self = $&pair.first)
        if drop_count != 1 { abort }
    }
    if drop_count != 2 { abort }
    {
        pair :: Pair = (.first = (), .second = ())
        first := $&pair.first
        first&= Empty()
        if drop_count != 3 { abort }
    }
    if drop_count != 5 { abort }
    {
        value :: Choice = ..none
        value = ..some(.pair = (.first = (), .second = ()))
    }
    if drop_count != 7 { abort }
    status_code = 42
}
