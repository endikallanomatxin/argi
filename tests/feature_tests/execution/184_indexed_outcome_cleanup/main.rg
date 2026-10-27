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

position :: UIntNative = 0
index_calls :: Int32 = 0

select_index := () -> (.result: UIntNative) {
    index_calls = index_calls + 1
    result = position
}

maybe_retarget := (.target: $&Resource, .enabled: Bool) -> (
    .result : (..initialized, ..preserved)
) {
    position = 1
    result = maybe_initialize(.target = target, .enabled = enabled)
}

zero_drops :: Int32 = 0

ZeroResource: Type = ()

implement Deinit#(ZeroResource) (
    .deinit = (.self: $&ZeroResource) -> () { zero_drops = zero_drops + 1 }
)

maybe_zero := (.target: $&ZeroResource, .enabled: Bool) -> (
    .result : (..initialized, ..preserved)
) {
    if enabled {
        target&= ZeroResource()
        result = ..initialized
        return
    }
    result = ..preserved
}

main := () -> (.status_code: Int32) {
    {
        values :: [1]Resource
        values[0] = Resource(.value = 1)
        deinit(.self = $&values[0])
        maybe_initialize(.target = $&values[0], .enabled = true)
    }
    if drops != 2 { abort }
    {
        values :: [1]Resource
        values[0] = Resource(.value = 1)
        deinit(.self = $&values[0])
        maybe_initialize(.target = $&values[0], .enabled = false)
    }
    if drops != 3 { abort }
    {
        values :: [2]Resource
        values[0] = Resource(.value = 1)
        values[1] = Resource(.value = 2)
        deinit(.self = $&values[0])
        position = 0
        maybe_retarget(.target = $&values[select_index()], .enabled = true)
    }
    if drops != 6 or index_calls != 1 or position != 1 { abort }
    {
        values :: [2]Resource
        values[0] = Resource(.value = 1)
        values[1] = Resource(.value = 2)
        deinit(.self = $&values[0])
        position = 0
        maybe_retarget(.target = $&values[select_index()], .enabled = false)
    }
    if drops != 8 or index_calls != 2 or position != 1 { abort }
    {
        values :: [2]ZeroResource
        values[0] = ZeroResource()
        values[1] = ZeroResource()
        deinit(.self = $&values[0])
        maybe_zero(.target = $&values[0], .enabled = true)
    }
    if zero_drops != 3 { abort }
    {
        values :: [2]ZeroResource
        values[0] = ZeroResource()
        values[1] = ZeroResource()
        deinit(.self = $&values[0])
        maybe_zero(.target = $&values[0], .enabled = false)
    }
    if zero_drops != 5 { abort }
    status_code = 42
}
