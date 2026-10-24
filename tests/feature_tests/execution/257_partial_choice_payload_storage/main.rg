drops :: Int32 = 0
whole_drops :: Int32 = 0

Resource: Type = (.value: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

Envelope: Type = (.choice: Choice, .marker: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
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

main() -> (.status_code: Int32) := {
    {
        envelope :: Envelope
        envelope.choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        match envelope.choice {
            ..pair $&payload {
                deinit(.self = $&payload&.left)
                if payload&.right.value != 2 { abort }
            }
            ..empty { abort }
        }
    }
    if drops != 2 or whole_drops != 0 { abort }
    {
        envelope :: Envelope
        envelope.choice = ..pair(.left = (.value = 3), .right = (.value = 4))
        match envelope.choice {
            ..pair $&payload {
                deinit(.self = $&payload&.left)
                payload&.left = (.value = 40)
            }
            ..empty { abort }
        }
        envelope.marker = 2
        match envelope.choice {
            ..pair&payload { if payload&.left.value + envelope.marker != 42 { abort } }
            ..empty { abort }
        }
    }
    if drops != 5 or whole_drops != 1 { abort }
    status_code = 42
}
