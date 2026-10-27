drops :: Int32 = 0

Resource := (.value: Int32)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

maybe := (.targets: [2] $&Resource, .enabled: Bool) -> (.result: (..initialized, ..vacant)) {
    copied ::= targets
    deinit(.self = copied[0])
    if enabled {
        copied[0]&= Resource(.value = 9)
        result = ..initialized
        return
    }
    result = ..vacant
}

main := () -> (.status_code: Int32) {
    {
        value :: Resource = Resource(.value = 1)
        other :: Resource = Resource(.value = 2)
        maybe(.targets = ($&value, $&other), .enabled = true)
    }
    if drops != 3 { abort }
    {
        value :: Resource = Resource(.value = 1)
        other :: Resource = Resource(.value = 2)
        maybe(.targets = ($&value, $&other), .enabled = false)
    }
    if drops != 5 { abort }
    status_code = 42
}
