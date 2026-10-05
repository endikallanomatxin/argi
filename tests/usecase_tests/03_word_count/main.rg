words ::= import ("./library")

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    assume file_system := system.file_system
    assume writer ::= $&BufferedWriter(
        $&system.terminal&.stdout
        view($&zeroed#([8192]UInt8)())
    )
    #defer flush(writer)!

    argc ::= length(system.args).count
    if argc < 2 or argc > 3 {
        print("Usage: word-count <directory> [maximum-file-bytes]")!
        return
    }

    limit :: UIntNative = 1048576
    if argc == 3 {
        limit = parse_uintnative(argument_view_at(system.args, 2))!
    }

    counts ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        StringHashPolicy()
    )!
    words.count_directory(
        $&counts
        argument_view_at(system.args, 1)
        limit
        view($&zeroed#([8192]UInt8)())
    )!

    for entry in counts {
        print(entry.value&, .terminator = "\t")!
        print(as_view(entry.key))!
    }
}
