main(.system: System) -> !Void = ..ok Void() := {
    write(.self = $&system.terminal&.stdout, .text = "ready\n")!
}
