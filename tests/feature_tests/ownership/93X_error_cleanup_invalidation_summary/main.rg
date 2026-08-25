..failure

Resource : Type = (
    .value: Int32
)

fail() -> (.result: Errable#(.t: Void, .reasons: (..failure))) := {
    result = ..error(.reason = ..failure)
}

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

run(.self: $&Resource) -> !() := {
    #defer deinit(.self = self)
    fail()!
}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer ::= &resource
    outcome ::= run(.self = $&resource)
    read(.value = pointer)
    if is(.value = outcome, .variant = ..error) {
        status_code = 0
    } else {
        status_code = 1
    }
}
