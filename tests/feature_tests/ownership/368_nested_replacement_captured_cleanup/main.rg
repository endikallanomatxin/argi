..missing
order :: Int32 = 0

Resource: Type = (.id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        order = order * 10 + self&.id
    }
)

make() -> (.result: Errable#(.t: Resource, .reasons: (..missing))) := {
    result = ..error(.reason = ..missing)
}

main() -> (.status_code: Int32 = 0) := {
    {
        outer :: Resource = Resource(.id = 1)
        inner :: Resource = Resource(.id = 2)
        selected := $&outer
        selected&= make() handle error, value {
            guard ::= Resource(.id = 5)
            nested := $&inner
            nested&= Resource(.id = 3)
            if order != 2 { abort }
            value = Resource(.id = 4)
        }
        if order != 251 or selected&.id != 4 or inner.id != 3 { abort }
    }
    if order != 25134 { abort }
    status_code = 42
}
