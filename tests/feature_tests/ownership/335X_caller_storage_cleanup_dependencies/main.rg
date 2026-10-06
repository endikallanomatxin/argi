Counter: Type = (.external: $&Int32, .alive: Bool)

Counter deinit(.self: $&Counter) -> () := {
    self&.alive = false
    self&.external&= self&.external&+ 100
}

Resource: Type = (.counter: $&Counter)

Resource deinit(.self: $&Resource) -> () := {
    if self&.counter&.alive == false { abort }
    self&.counter&.external&= self&.counter&.external&+ 1
}

make(.counter: $&Counter) -> (.result: &Resource) := {
    resource :: Resource = (.counter = counter)
    result = &resource
}

relay(.external: $&Int32) -> (.result: &Resource) := {
    counter :: Counter = (.external = external, .alive = true)
    reference ::= make(.counter = $&counter)
    result = reference
}

direct(.external: $&Int32) -> (.result: &Resource) := {
    counter :: Counter = (.external = external, .alive = true)
    result = make(.counter = $&counter)
}

main() -> (.status_code: Int32 = 0) := {
    external :: Int32 = 0
    {
        first ::= relay(.external = $&external)
        second ::= direct(.external = $&external)
        if external != 0 { status_code = 1 }
    }
    if external != 202 { status_code = 2 }
}
