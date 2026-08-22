Getter : Abstract = (
    get(.self: &Self) -> (.result: &Int32)
)

Resource : Type = (
    .value: Int32
)

get(.self: &Resource) -> (.result: &Int32) := {
    result = &self&.value
}

Resource implements Getter

forward(.self: &Getter) -> (.result: &Int32) := {
    result = get(.self = self).result
}

invalidate(.self: $$&Resource) -> () := {
    self&.value = 0
}

read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := forward(.self = &resource).result
    invalidate(.self = $$&resource)
    read(.value = pointer)
    status_code = 0
}
