main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator := system.page_allocator
    keys: [32]StringView = (
        "entry_00000_end",
        "entry_00001_end",
        "entry_00002_end",
        "entry_00003_end",
        "entry_00004_end",
        "entry_00005_end",
        "entry_00006_end",
        "entry_00007_end",
        "entry_00008_end",
        "entry_00009_end",
        "entry_00010_end",
        "entry_00011_end",
        "entry_00012_end",
        "entry_00013_end",
        "entry_00014_end",
        "entry_00015_end",
        "entry_00016_end",
        "entry_00017_end",
        "entry_00018_end",
        "entry_00019_end",
        "entry_00020_end",
        "entry_00021_end",
        "entry_00022_end",
        "entry_00023_end",
        "entry_00024_end",
        "entry_00025_end",
        "entry_00026_end",
        "entry_00027_end",
        "entry_00028_end",
        "entry_00029_end",
        "entry_00030_end",
        "entry_00031_end"
    )
    bytes: [4]UInt8 = (0, 127, 194, 128)
    text ::= unwrap_or_abort(.value = string_from_bytes(.bytes = view(&bytes)))
    map ::= unwrap_or_abort(.value = HashMap#(.key: StringView, .value: Int32)(.capacity = 1))
    index :: UIntNative = 0
    while index < 32 {
        unwrap_or_abort(.value = put($&map, .key = keys[index], .value = 7))
        index = index + 1
    }
    index = 0
    while index < 32 {
        match get(&map, .key = keys[index]).result {
            ..none { abort }
            ..some found { if found.value != 7 { abort } }
        }
        index = index + 1
    }
    unwrap_or_abort(.value = put($&map, .key = keys[15], .value = 9))
    index = 0
    while index < 32 {
        match extract($&map, .key = keys[index]).result {
            ..none { abort }
            ..some ~found {
                entry ::= ~found.value
                if equals(.left = entry.key, .right = keys[index]).ok == false { abort }
                if index == 15 {
                    if entry.value != 9 { abort }
                } else {
                    if entry.value != 7 { abort }
                }
            }
        }
        if contains(&map, .key = keys[index]).ok { abort }
        index = index + 1
    }
    unwrap_or_abort(.value = put($&map, .key = view(&text), .value = 11))
    match get(&map, .key = view(&text)).result {
        ..none { abort }
        ..some found { if found.value != 11 { abort } }
    }
    if contains(&map, .key = "").ok { abort }
    if remove($&map, .key = view(&text)).removed == false { abort }
}
