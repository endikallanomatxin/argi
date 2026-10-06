..missing

fail() -> (.result: Errable#(Int32, (..missing))) := {
    result = ..error(.reason = ..missing)
}

recover(.initialize: Bool) -> (.result: Int32) := {
    result = fail() handle error, value {
        if initialize { value = 7 }
    }
}

main() -> () := { recover(false) }
