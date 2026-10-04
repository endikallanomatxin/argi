main(.system: System) -> !Void = ..ok Void() := {
    directory ::= Directory(.self = system.file_sys, .path = ".")!
    copy ::= directory
}
