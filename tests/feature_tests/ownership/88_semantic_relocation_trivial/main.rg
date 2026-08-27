main() -> (.status_code: Int32) := {
    source :: Int32 = 7
    destination :: Int32
    relocate(.source = $&source, .destination = $&destination)
    if destination == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
}
