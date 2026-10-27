drops :: Int32 = 0

Resource := (.value: Int32)

implement Deinit#(Resource) (
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

position :: UIntNative = 0
index_calls :: Int32 = 0

select_index := () -> (.result: UIntNative) {
    index_calls = index_calls + 1
    result = position
}

maybe_nested := (.args: (.nested: (.target: $&Resource)), .enabled: Bool) -> (
    .result : (..initialized, ..vacant)
) {
    position = 1
    if enabled {
        args.nested.target&= Resource(.value = 9)
        result = ..initialized
        return
    }
    result = ..vacant
}

main := () -> (.status_code: Int32) {
    {
        values :: [1]Resource
        values[0] = Resource(.value = 1)
        deinit(.self = $&values[0])
        maybe_record(.args = (.target = $&values[0]), .enabled = true)
    }
    if drops != 2 { abort }
    {
        values :: [1]Resource
        values[0] = Resource(.value = 1)
        deinit(.self = $&values[0])
        maybe_record(.args = (.target = $&values[0]), .enabled = false)
    }
    if drops != 3 { abort }
    {
        values :: [2]Resource
        values[0] = Resource(.value = 1)
        values[1] = Resource(.value = 2)
        deinit(.self = $&values[0])
        position = 0
        maybe_nested(.args = (.nested = (.target = $&values[select_index()])), .enabled = true)
    }
    if drops != 6 or index_calls != 1 or position != 1 { abort }
    {
        values :: [2]Resource
        values[0] = Resource(.value = 1)
        values[1] = Resource(.value = 2)
        deinit(.self = $&values[0])
        position = 0
        maybe_nested(.args = (.nested = (.target = $&values[select_index()])), .enabled = false)
    }
    if drops != 8 or index_calls != 2 or position != 1 { abort }
    status_code = 42
}
