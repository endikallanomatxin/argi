Touched<.Participant: Type>: Contract = (
    .touch : (.self: $&Participant) -> ()
)

Thing := (
    .marker : Int32 = 0
)

_impl_touch_Thing := (.self: $&Thing) -> () {
}

implement Touched<Thing> (.touch = _impl_touch_Thing)

main := (.system: System) -> (.status_code: Int32) {
    thing :: Thing = (
        .marker = 0
    )
    touch(.self = $&thing)
    status_code = 0
}
