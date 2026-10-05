main(.system: System) -> !Void = ..ok Void() := {
    directory ::= Directory(.self = system.file_system, .path = ".")!
    copy ::= directory
}
