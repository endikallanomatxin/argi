spin() -> (.result: Int32 = 0) := { while true {} }

main() -> (.status_code: Int32 = 0) := {
    status_code = #run spin()
}
