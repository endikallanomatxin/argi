Pair := (.left: Int32, .right: Int32 = 22)

calls :: Int32 = 0

select := (.value: $&Pair) -> (.result: $&Pair) {
    calls = calls + 1
    result = value
}

main := () -> (.status_code: Int32) {
    value :: Pair = (.left = 1, .right = 2)
    pointer ::= select($&value)
    pointer&= (.left = 20)
    [select($&value)]&= (.left = 20)
    if calls != 2 { abort }
    values :: [2]Pair = ((.left = 0, .right = 0), (.left = 0, .right = 0))
    values[1] = (.left = 20)
    if values[1].right != 22 { abort }
    status_code = value.left + value.right
}
