Receive#(.Receiver: Type): Contract = (
    .Message : Type
    .receive : (.receiver: $&Receiver, .message: Message) -> ()
)

Message := (.left: Int32, .right: Int32)

Receiver := (.total: Int32)

implement Receive#(Receiver) (
    .Message : Type = Message
    .receive = (.receiver: $&Receiver, .message: Message) -> () {
        receiver&.total = message.left + message.right
    }
)

main := () -> (.status_code: Int32 = 0) {
    receiver ::= Receiver(.total = 0)
    receive($&receiver, .message = (.left = 20, .right = 22))
    if receiver.total != 42 { abort }
}
