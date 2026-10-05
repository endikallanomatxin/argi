Tracked: Type = ()

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

main() -> (.status_code: Int32 = 0) := {
    while true {
        owner ::= Tracked()
        {
            nested ::= Tracked()
            break
        }
    }
    if drops != 2 { abort }
    count :: Int32 = 0
    while count < 3 {
        owner ::= Tracked()
        count = count + 1
        continue
    }
    if drops != 5 { abort }
    while true {
        outer ::= Tracked()
        while true {
            inner ::= Tracked()
            break
        }
        if drops != 6 { abort }
        break
    }
    if drops != 7 { abort }
}
