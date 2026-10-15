struct Packet { double value; int count; void *context; };
typedef struct Packet (*Transformer)(struct Packet);
int argi_typed_callback_probe(Transformer callback) {
    int context = 17;
    struct Packet packet = {1.5, 73, &context};
    struct Packet result = callback(packet);
    if (result.value != packet.value) return 1;
    if (result.count != packet.count + 1) return 2;
    if (result.context != packet.context || context != 17) return 3;
    return 0;
}

struct Packet argi_typed_callback_packet(void) {
    struct Packet packet = {3.5, 8, 0};
    return packet;
}
