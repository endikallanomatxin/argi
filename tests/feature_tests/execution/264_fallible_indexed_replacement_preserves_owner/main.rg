..stop

drops :: Int32 = 0
whole_drops :: Int32 = 0

Resource: Type = (.id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

implement Deinit#(Choice) (
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

indices :: Int32 = 0

select_index(.selection: $&UIntNative) -> (.result: UIntNative) := {
    indices = indices + 1
    result = selection&
}

build_choice(.selection: $&UIntNative, .fail: Bool) -> (.result: Errable#(Choice, (..stop))) := {
    selection&= 1
    value :: Choice = ..pair(.left = Resource(.id = 7), .right = maybe_resource(.fail = fail)!)
    result = ..ok ~value
}

maybe_resource(.fail: Bool) -> (.result: Errable#(Resource, (..stop))) := {
    if fail { result = ..error(.reason = ..stop) } else { result = ..ok Resource(.id = 14) }
}

replace(.values: $&[2]Choice, .selection: $&UIntNative, .fail: Bool) -> (
    .result : Errable#(Int32, (..stop))
) := {
    values&[select_index(.selection = selection)] = build_choice(
        .selection = selection, .fail = fail
    )!
    result = ..ok 42
}

main() -> (.status_code: Int32) := {
    assume error_tracer ::= $&noop_error_tracer
    {
        values :: [2]Choice = (
            ..pair(.left = (.id = 1), .right = (.id = 2)),
            ..pair(.left = (.id = 3), .right = (.id = 4))
        )
        selection :: UIntNative = 0
        replace(.values = $&values, .selection = $&selection, .fail = true) handle error {
            match error.reason { ..stop {} }
        }
        if drops != 7 or whole_drops != 0 or indices != 1 or selection != 1 { abort }
        match values[0] {
            ..pair&payload { if payload&.left.id != 1 { abort } }
            ..empty { abort }
        }
        selection = 0
        replace(.values = $&values, .selection = $&selection, .fail = false) handle error {
            abort
        }
        if drops != 10 or whole_drops != 1 or indices != 2 or selection != 1 { abort }
        match values[0] {
            ..pair&payload { if payload&.left.id != 7 { abort } }
            ..empty { abort }
        }
        match values[1] {
            ..pair&payload { if payload&.left.id != 3 { abort } }
            ..empty { abort }
        }
    }
    if drops != 38 or whole_drops != 3 { abort }
    status_code = 42
}
