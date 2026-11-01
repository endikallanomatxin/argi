http := import ("network/http")

App := (.saved: ?$&http.Request)

implement http.Handler#(App) (
    .Reasons : Type = (..failure)
    .handle  = (.self: $&App, .request: $&http.Request) -> (
        .result : Errable#(Void, Reasons) = ..ok Void()
    ) {
        self&.saved = ..some(.value = request)
    }
)

main := () -> (.status_code: Int32 = 0) {
    input: StringView = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
    reader ::= ByteReader(.bytes = string_bytes(.text = input))
    bytes :: [256]UInt8 = zeroed#([256]UInt8)()
    writer ::= ByteWriter(.bytes = view($&bytes))
    app :: App = (.saved = ..none)
    unwrap_or_abort(
        .value = http.serve_stream(.reader = $&reader, .writer = $&writer, .handler = $&app)
    )
    match app.saved {
        ..none { abort }
        ..some item { if http.content_finished(.self = item.value).ok { abort } }
    }
}
