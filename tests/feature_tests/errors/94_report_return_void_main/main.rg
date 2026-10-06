..missing
drops :: Int32 = 0

Owner: Type = (.value: Int32)

Owner deinit(.self: $&Owner) -> () := { drops = drops + 1 }

attempt(.fail: Bool) -> (.result: Errable#(Owner, (..missing))) := {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok Owner(7) }
}

work(.system: System) -> () := {
    assume writer ::= $&system.terminal&.stderr
    owner ::= attempt(false)!!!
    if owner.value != 7 { abort }
    attempt(true)!!!
    abort
}

main(.system: System) -> () := {
    work(system)
    if drops != 1 { abort }
}
