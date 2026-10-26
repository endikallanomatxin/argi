..stop

drops :: Int32 = 0
whole_drops :: Int32 = 0

Resource := (.id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

implement Deinit<Choice> (
    .deinit = (.self: $&Choice) -> () {
        whole_drops = whole_drops + 1
        match self&{
            ..pair $&payload {
                deinit(.self = $&payload&.left)
                deinit(.self = $&payload&.right)
            }
            ..empty {}
        }
    }
)

fail_resource := (.fail: Bool) -> (.result: Errable<Resource, (..stop)>) {
    if fail { result = ..error(.reason = ..stop) } else { result = ..ok Resource(.id = 14) }
}

build_choice := (.fail: Bool) -> (.result: Errable<Choice, (..stop)>) {
    value :: Choice = ..pair(
        .left  = Resource(.id = 7)
        .right = fail_resource(.fail = fail)!
    )
    result = ..ok ~value
}

consume := (.left: Resource, .right: Resource) -> (.result: Int32) {
    first ::= ~left
    second ::= ~right
    result = 42
}

build_call := (.fail: Bool) -> (.result: Errable<Int32, (..stop)>) {
    result = ..ok consume(.left = Resource(.id = 7), .right = fail_resource(.fail = fail)!)
}

build_array := (.fail: Bool) -> (.result: Errable<Int32, (..stop)>) {
    values :: [2]Resource = (Resource(.id = 7), fail_resource(.fail = fail)!)
    result = ..ok 42
}

handles :: Int32 = 0

State: Type = ()

Consumer<.StateType: Type>: Contract = (
    .consume : (.self: $&StateType, .left: Resource, .right: Resource) -> (.result: Int32) where {}
)

implement Consumer<State> (
    .consume = (.self: $&State, .left: Resource, .right: Resource) -> (.result: Int32) {
        first ::= ~left
        second ::= ~right
        result = 42
    }
)

select_handle := (.handle: $&Virtual<.contract: Consumer>) -> (
    .result : $&Virtual<.contract: Consumer>
) {
    handles = handles + 1
    result = handle
}

build_virtual := (.handle: $&Virtual<.contract: Consumer>, .fail: Bool) -> (
    .result: Errable<Int32, (..stop)>
) {
    result = ..ok Consumer<>.consume(
        .self  = select_handle(.handle = handle)
        .left  = Resource(.id = 7)
        .right = fail_resource(.fail = fail)!
    )
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    build_choice(.fail = true) handle error {
        match error.reason { ..stop {} }
    }
    if drops != 7 or whole_drops != 0 { abort }
    build_choice(.fail = false) handle error { abort }
    if drops != 28 or whole_drops != 1 { abort }
    build_call(.fail = true) handle error { match error.reason { ..stop {} } }
    if drops != 35 { abort }
    build_call(.fail = false) handle error { abort }
    if drops != 56 { abort }
    build_array(.fail = true) handle error { match error.reason { ..stop {} } }
    if drops != 63 { abort }
    build_array(.fail = false) handle error { abort }
    if drops != 84 or whole_drops != 1 { abort }
    state :: State = ()
    handle ::= to_virtual<.contract: Consumer>(.value = $&state)
    build_virtual(.handle = $&handle, .fail = true) handle error {
        match error.reason { ..stop {} }
    }
    if drops != 91 or handles != 1 { abort }
    build_virtual(.handle = $&handle, .fail = false) handle error { abort }
    if drops != 112 or handles != 2 { abort }
    status_code = 42
}
