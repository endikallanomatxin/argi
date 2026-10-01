main(.system: System) -> (.status_code: Int32 = 0) := {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    empty :: StringView = ""
    alpha :: StringView = "alpha"
    if string_hash_map_hash(.key = &empty).hash != 7 { abort }
    if string_hash_map_hash(.key = &alpha).hash != 9186341 { abort }
    bytes : [4]UInt8 = (0, 127, 128, 255)
    binary :: StringView = (.data = &bytes[0], .length = 4)
    if string_hash_map_hash(.key = &binary).hash != 8850789 { abort }
    keys : [32]StringView = ("entry_00000_end", "entry_00001_end", "entry_00002_end", "entry_00003_end", "entry_00004_end", "entry_00005_end", "entry_00006_end", "entry_00007_end", "entry_00008_end", "entry_00009_end", "entry_00010_end", "entry_00011_end", "entry_00012_end", "entry_00013_end", "entry_00014_end", "entry_00015_end", "entry_00016_end", "entry_00017_end", "entry_00018_end", "entry_00019_end", "entry_00020_end", "entry_00021_end", "entry_00022_end", "entry_00023_end", "entry_00024_end", "entry_00025_end", "entry_00026_end", "entry_00027_end", "entry_00028_end", "entry_00029_end", "entry_00030_end", "entry_00031_end")
    buckets : [64]UIntNative = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    index :: UIntNative = 0
    while index < 32 {
        bucket ::= string_hash_map_bucket_index(.bucket_count = 64, .key = &keys[index]).index
        buckets[bucket] = buckets[bucket] + 1
        if buckets[bucket] > 4 { abort }
        index = index + 1
    }
    map ::= StringHashMap#(.value: Int32)(.capacity = 1)
    index = 0
    while index < 32 {
        put#(.value: Int32)(.self = $&map, .key = &keys[index], .value = 7)
        index = index + 1
    }
    index = 0
    while index < 32 {
        match get#(.value: Int32)(.self = &map, .key = &keys[index]).value {
            ..none { abort }
            ..some payload { if payload.value != 7 { abort } }
        }
        index = index + 1
    }
    put#(.value: Int32)(.self = $&map, .key = &keys[15], .value = 9)
    match get#(.value: Int32)(.self = &map, .key = &keys[15]).value {
        ..none { abort }
        ..some payload { if payload.value != 9 { abort } }
    }
    index = 0
    while index < 32 {
        match delete#(.value: Int32)(.self = $&map, .key = &keys[index]).value {
            ..none { abort }
            ..some payload {
                if index == 15 {
                    if payload.value != 9 { abort }
                } else {
                    if payload.value != 7 { abort }
                }
            }
        }
        if has#(.value: Int32)(.self = &map, .key = &keys[index]).ok { abort }
        index = index + 1
    }
}
