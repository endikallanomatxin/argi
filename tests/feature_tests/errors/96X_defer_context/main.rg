fail := () -> !Void = ..ok Void() {}

main := () -> () { defer fail()!! "cleanup" }
