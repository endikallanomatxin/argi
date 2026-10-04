..startup_failed
fail() -> !Void := {
    result = ..error(.reason = ..startup_failed)
}
main() -> !Void = ..ok Void() := {
    fail() !! "starting application"
}
