Touched : Abstract = (
    touch(
        .self: $&Self,
    ) -> ()
)

Thing : Type = (
    .marker: Int32 = 0
)

touch(
    .self: $&Thing,
) -> () := {
}

Thing implements Touched

main(.system: System = System()) -> (.status_code: Int32) := {
    thing :: Thing = (
        .marker = 0
    )
    touch(.self = $&thing)
    status_code = 0
}
