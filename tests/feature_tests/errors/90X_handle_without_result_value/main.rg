..missing

attempt() -> (.result: Errable#(Int32, (..missing))) := { result = ..ok 7 }

main() -> () := {
    value: Int32 = attempt() handle error {}
}
