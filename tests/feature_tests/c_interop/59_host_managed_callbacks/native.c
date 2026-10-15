struct Packet {
    double value;
    int count;
    void *context;
};

typedef int (*AddCallback)(int, int);
typedef struct Packet (*PacketCallback)(struct Packet);
extern int argi_callback_add(int, int);
extern struct Packet argi_callback_packet(struct Packet);

/* The host selects and invokes callbacks through C function pointers. */
static int exercise(AddCallback add, PacketCallback transform) {
    int context = 17;
    struct Packet packet = {1.5, 0, &context};
    double expected = packet.value;
    for (int i = 0; i < 8; ++i) {
        if (add(i, 31) != i + 31) return 1;
        packet = transform(packet);
        expected *= 2.0;
        if (packet.value != expected) return 2;
        if (packet.count != 3 * (i + 1)) return 3;
        if (packet.context != &context) return 4;
    }
    return context == 17 ? 0 : 5;
}

int argi_exercise_callbacks(void) {
    return exercise(argi_callback_add, argi_callback_packet);
}
