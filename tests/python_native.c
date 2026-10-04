/* Standalone ownership and error-boundary probe for the optional adapter.
   Compile with the same Python headers and embedding library as runtime.c. */
#include "../more/python/runtime.c"
#include <assert.h>
#if !defined(_WIN32)
#include <pthread.h>
static void *wrong_thread(void *context) {
    assert(!_argi_python_scalar((uintptr_t)context, 0, 0, 0, 0));
    return NULL;
}
#endif
int main(void) {
    const uint8_t program[] = "python3", empty[] = "";
    uintptr_t context = _argi_python_start(program, sizeof(program) - 1, empty, 0);
    assert(context);
    assert(!_argi_python_start(program, sizeof(program) - 1, empty, 0));
    PyObject *list = _argi_python_scalar(context, 5, 0, 0, 0);
    assert(list && Py_REFCNT(list) == 1);
    PyObject *clone = _argi_python_clone(context, list);
    assert(clone == list && Py_REFCNT(list) == 2);
    _argi_python_release(context, clone);
    assert(Py_REFCNT(list) == 1);
    PyObject *tuple = _argi_python_tuple(context, 1);
    assert(!_argi_python_tuple_set(context, tuple, 0, list));
    assert(Py_REFCNT(list) == 2);
    assert(_argi_python_tuple_set(context, tuple, 1, list) == -1);
    assert(Py_REFCNT(list) == 2 && !PyErr_Occurred());
    _argi_python_release(context, tuple);
    assert(Py_REFCNT(list) == 1);
    const uint8_t invalid[] = {0xff};
    assert(!_argi_python_string(context, invalid, 1));
    assert(!PyErr_Occurred());
    uintptr_t length = _argi_python_error_size(context);
    assert(length);
    uint8_t *error = malloc(length + 1);
    assert(error && !_argi_python_error_copy(context, error, length));
    error[length] = 0;
    assert(strstr((char *)error, "UnicodeDecodeError"));
    free(error);
    uintptr_t snapshot = _argi_python_error_snapshot(context);
    assert(_argi_python_exception_size(snapshot, 0) == strlen("UnicodeDecodeError"));
    const uint8_t nul[] = {'a', 0, 'b'};
    assert(!_argi_python_import(context, nul, sizeof(nul)));
    PyObject *bytes = _argi_python_bytes(context, nul, sizeof(nul));
    assert(bytes);
    uint8_t destination[] = {99, 99, 99, 99};
    assert(_argi_python_text_copy(context, bytes, 1, destination, 2) == -1);
    assert(destination[0] == 99 && destination[3] == 99);
    assert(!_argi_python_text_copy(context, bytes, 1, destination, 3));
    assert(!memcmp(destination, nul, 3) && destination[3] == 99);
    _argi_python_release(context, bytes);
    _argi_python_release(context, list);
#if !defined(_WIN32)
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, wrong_thread, (void *)context));
    assert(!pthread_join(thread, NULL));
#endif
    assert(!_argi_python_stop(context));
    assert(!Py_IsInitialized());
    uintptr_t snapshot_length = _argi_python_exception_size(snapshot, 1);
    assert(snapshot_length);
    uint8_t *snapshot_message = malloc(snapshot_length + 1);
    assert(snapshot_message);
    assert(!_argi_python_exception_copy(snapshot, 1, snapshot_message, snapshot_length));
    snapshot_message[snapshot_length] = 0;
    assert(strstr((char *)snapshot_message, "utf-8"));
    free(snapshot_message);
    _argi_python_exception_release(snapshot);
    assert(!_argi_python_start(program, sizeof(program) - 1, empty, 0));
    return 0;
}
