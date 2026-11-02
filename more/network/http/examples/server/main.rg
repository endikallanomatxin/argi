http := import ("network/http")

App: Type = ()

implement http.Handler#(App) (
    .Reasons : Type = http.HttpReasons
    .handle  = (.self: $&App, .request: $&http.Request) -> (
        .result : Errable#(Void, Reasons) = ..ok Void()
    ) {
        http.respond_text(.self = request, .text = "Hello from Argi!\n")!
    }
)

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    app :: App = ()
    http.serve(.handler = $&app, .network = system.network)!!!
}
