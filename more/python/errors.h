#ifndef ARGI_PYTHON_ERRORS_H
#define ARGI_PYTHON_ERRORS_H

/* Immutable native text snapshots outlive Python without retaining PyObjects.
   The context and every Argi Exception own one reference. Static fallbacks have
   zero references and require no allocation or cleanup. */
struct argi_python_error {
    size_t references;
    const char *parts[3];
    size_t lengths[3];
};
static struct argi_python_error empty_error = {0, {"", "", ""}, {0, 0, 0}};
static struct argi_python_error memory_error = {
    0, {"MemoryError", "Cannot retain Python exception details", "MemoryError: Cannot retain Python exception details"},
    {sizeof("MemoryError") - 1, sizeof("Cannot retain Python exception details") - 1,
     sizeof("MemoryError: Cannot retain Python exception details") - 1}
};
static struct argi_python_error *initialization_failure;

static struct argi_python_error *retain_error(struct argi_python_error *error) {
    if (!error) return &empty_error;
    if (error->references) error->references++;
    return error;
}
static void release_error(struct argi_python_error *error) {
    if (!error || !error->references || --error->references) return;
    for (size_t i = 0; i < 3; i++) free((void *)error->parts[i]);
    free(error);
}
static struct argi_python_error *make_error(const char *type, size_t type_length,
        const char *message, size_t message_length, const char *traceback, size_t traceback_length) {
    struct argi_python_error *error = calloc(1, sizeof(*error));
    if (!error) return &memory_error;
    error->references = 1;
    const char *parts[3] = {type, message, traceback};
    size_t lengths[3] = {type_length, message_length, traceback_length};
    for (size_t i = 0; i < 3; i++) {
        if (lengths[i] == SIZE_MAX) { release_error(error); return &memory_error; }
        char *copy = malloc(lengths[i] + 1);
        if (!copy) { release_error(error); return &memory_error; }
        memcpy(copy, parts[i], lengths[i]);
        copy[lengths[i]] = 0;
        error->parts[i] = copy;
        error->lengths[i] = lengths[i];
    }
    return error;
}
static void replace_error(struct argi_python_error **slot, struct argi_python_error *error) {
    release_error(*slot);
    *slot = error;
}
static void set_initialization_error(const char *message) {
    replace_error(&initialization_failure, make_error("InitializationError", sizeof("InitializationError") - 1,
        message, strlen(message), message, strlen(message)));
}
#endif
