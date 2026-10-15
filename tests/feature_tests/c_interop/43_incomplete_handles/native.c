struct Handle { int value; };
static struct Handle handle = {42};
struct Handle *argi_c_handle_create(void) { return &handle; }
int argi_c_handle_read(struct Handle *value) { return value ? value->value : 0; }
extern struct Handle *argi_c_handle_export(struct Handle *);
int argi_c_handle_probe(void) {
    return argi_c_handle_export(&handle) != &handle || argi_c_handle_export(0) != 0;
}
