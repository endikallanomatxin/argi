Counter: Type = (.external: $&Int32, .alive: Bool)

Resource: Type = (.counter: $&Counter, .value: Int32)

Counter deinit(.self: $&Counter) -> () := {
    self&.alive = false
    self&.external&= self&.external&+ 100
}

Resource deinit(.self: $&Resource) -> () := {
    if self&.counter&.alive == false { abort }
    self&.counter&.external&= self&.counter&.external&+ 1
}

make(.counter: $&Counter, .value: Int32) -> (.result: Resource) := {
    result = Resource(counter, value)
}

relay(.resource: &Resource) -> (.result: &Resource) := {
    result = resource
}

main() -> (.status_code: Int32 = 0) := {
    external :: Int32 = 0

    {
        counter ::= Counter($&external, true)
        first ::= make($&counter, 7)
        second ::= make($&counter, 11)
        reference ::= relay(&first)

        if reference&.value != 7 or second.value != 11 or external != 0 {
            status_code = 1
            return
        }
    }

    if external != 102 { status_code = 2 }
}
