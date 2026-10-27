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
        owners :: [2]Resource
        owners[0] = Resource(.value = 1)
        owners[1] = Resource(.value = 2)
        maybe(.targets = ($&owners[0], $&owners[1]), .enabled = true)
    }
    if drops != 3 { abort }
    {
        owners :: [2]Resource
        owners[0] = Resource(.value = 1)
        owners[1] = Resource(.value = 2)
        maybe(.targets = ($&owners[0], $&owners[1]), .enabled = false)
    }
    if drops != 5 { abort }
    status_code = 42
}
