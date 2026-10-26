drops :: Int32 = 0

Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)

maybe_initialize := (.target: $&Resource, .enabled: Bool) -> (
    .result : (..initialized, ..preserved)
) {
    if enabled {
        target&= Resource(.value = 9)
        result = ..initialized
        return
    }
    result = ..preserved
}

maybe_record := (.args: (.target: $&Resource), .enabled: Bool) -> (
    .result : (..initialized, ..preserved)
) {
    if enabled {
        args.target&= Resource(.value = 9)
        result = ..initialized
        return
    }
    result = ..preserved
}

main := () -> (.status_code: Int32) {
    {
        value :: Resource = Resource(.value = 1)
        deinit(.self = $&value)
        maybe_initialize(.target = $&value, .enabled = true)
    }
    if drops != 2 { abort }
    {
        value :: Resource = Resource(.value = 1)
        deinit(.self = $&value)
        maybe_initialize(.target = $&value, .enabled = false)
    }
    if drops != 3 { abort }
    {
        value :: Resource = Resource(.value = 1)
        deinit(.self = $&value)
        maybe_record(.args = (.target = $&value), .enabled = true)
    }
    if drops != 5 { abort }
    {
        value :: Resource = Resource(.value = 1)
        deinit(.self = $&value)
        maybe_record(.args = (.target = $&value), .enabled = false)
    }
    if drops != 6 { abort }
    status_code = 42
}
