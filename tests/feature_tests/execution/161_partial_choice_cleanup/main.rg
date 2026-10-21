drops :: Int32 = 0
whole_drops :: Int32 = 0

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

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

Envelope: Type = (.choice: Choice, .sibling: Resource)

implement Deinit#(Envelope) (.deinit = (.self: $&Envelope) -> () { abort })

consume_left(.choice: $&Choice, .consume: Bool) -> () := {
    if consume {
        match choice&{
            ..pair $&payload { deinit(.self = $&payload&.left) }
            ..empty {}
        }
    }
}

main() -> (.status_code: Int32) := {
    if true {
        choice :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        match choice {
            ..pair $&payload { deinit(.self = $&payload&.left) }
            ..empty {}
        }
    }
    if drops != 2 or whole_drops != 0 { abort }
    if true {
        choice :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
    }
    if drops != 4 or whole_drops != 1 { abort }
    if true {
        choice :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        match choice {
            ..pair $&payload {
                deinit(.self = $&payload&.left)
                payload&.left = (.value = 3)
            }
            ..empty {}
        }
    }
    if drops != 7 or whole_drops != 2 { abort }
    if true {
        envelope :: Envelope = (
            .choice  = ..pair(.left = (.value = 1), .right = (.value = 2))
            .sibling = (.value = 3)
        )
        match envelope.choice {
            ..pair $&payload { deinit(.self = $&payload&.left) }
            ..empty {}
        }
    }
    if drops != 10 or whole_drops != 2 { abort }
    if true {
        choice :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        consume_left(.choice = $&choice, .consume = true)
    }
    if drops != 12 or whole_drops != 2 { abort }
    if true {
        choice :: Choice = ..pair(.left = (.value = 1), .right = (.value = 2))
        consume_left(.choice = $&choice, .consume = false)
    }
    if drops != 14 or whole_drops != 3 { abort }
    status_code = 42
}
