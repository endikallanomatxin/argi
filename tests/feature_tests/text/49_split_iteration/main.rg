count_computed#(.t: Type)(.text: t) -> (.count: UIntNative = 0) := {
    for segment in unwrap_or_abort(.value = split(text, .separator = ",")) {
        count = count + 1
    }
}

run_main() -> !Void = ..ok Void() := {
    if count_computed(",a,").count != 3 { abort }

    parts ::= split(",a,,b,", .separator = ",")!
    index :: UIntNative = 0
    for part in parts {
        if index == 1 and part != "a" { abort }
        if index == 3 and part != "b" { abort }
        if index != 1 and index != 3 and part != "" { abort }
        index = index + 1
    }
    if index != 5 { abort }
    if next($&parts).value != "" { abort }

    index = 0
    for part in parts {
        if index == 0 and part != "a" { abort }
        if index == 2 and part != "b" { abort }
        index = index + 1
    }
    if index != 4 { abort }
    if next($&parts).value != "a" { abort }

    count :: UIntNative = 0
    for part in split("", .separator = ",")! {
        if part != "" { abort }
        count = count + 1
    }
    if count != 1 { abort }
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
