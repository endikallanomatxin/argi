Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

Envelope: Type = (.resource: Resource)

replace(.target: $&Envelope, .counter: $&Counter) -> () := {
    target&= Envelope(.resource = Resource(.counter = counter))
}

main() -> () := {
    counter :: Counter = Counter()
    owner :: Envelope = Envelope(.resource = Resource(.counter = $&counter))
    replace(.target = $&owner, .counter = $&counter)
}
