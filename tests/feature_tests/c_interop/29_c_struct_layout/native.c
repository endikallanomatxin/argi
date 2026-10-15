#include <stddef.h>

struct Payload {
    int tag;
    double value;
    unsigned char flag;
    unsigned char bytes[3];
    void *pointer;
};
struct Pair { int left; int right; };
extern int argi_c_payload_export(const struct Payload *payload);
size_t argi_c_payload_size(void) { return sizeof(struct Payload); }
double argi_c_payload_value(void) { return 1.5; }
int argi_c_payload_verify(const struct Payload *payload) {
    return payload->tag == 7 && payload->value == 1.5 && payload->flag == 3 &&
           payload->bytes[0] == 1 && payload->bytes[1] == 2 &&
           payload->bytes[2] == 3 && payload->pointer == NULL &&
           argi_c_payload_export(payload) == 7 ? 0 : 1;
}
void argi_c_payload_fill(struct Payload *payload) {
    payload->tag = 42;
    payload->flag = 5;
    payload->bytes[2] = 9;
}
int argi_c_pair_sum(const struct Pair *pair) { return pair->left + pair->right; }
