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
    PyObject *globals = PyDict_New();
    assert(globals);
    PyObject *executed = PyRun_String("import gc\nclass Replacement(Exception):\n    pass\nclass Mutating(Exception):\n    def __str__(self):\n        self.__class__ = Replacement\n        del globals()['Mutating']\n        gc.collect()\n        return 'mutated message'\nexception = Mutating('original message')\n", Py_file_input, globals, globals);
    assert(executed);
    Py_DECREF(executed);
    PyObject *mutating_exception = PyDict_GetItemString(globals, "exception");
    assert(mutating_exception);
    PyErr_SetObject((PyObject *)Py_TYPE(mutating_exception), mutating_exception);
    capture_error((struct argi_python *)context);
    uintptr_t mutation_snapshot = _argi_python_error_snapshot(context);
    uint8_t mutation_type[sizeof("Mutating")];
    assert(!_argi_python_exception_copy(mutation_snapshot, 0, mutation_type, sizeof(mutation_type)));
    assert(!memcmp(mutation_type, "Mutating", sizeof("Mutating") - 1));
    _argi_python_exception_release(mutation_snapshot);
    Py_DECREF(globals);
    int64_t numeric_source[] = {-1, 2, 300};
    int64_t numeric_destination[] = {99, 99, 99, 99};
    uintptr_t copied = 0;
    Py_ssize_t shape[] = {3, 1}, strides[] = {sizeof(int64_t), sizeof(int64_t)};
    Py_buffer view = {.buf = numeric_source, .len = sizeof(numeric_source), .readonly = 1,
        .itemsize = sizeof(int64_t), .format = "q", .ndim = 1, .shape = shape, .strides = strides};
    PyObject *numeric = PyMemoryView_FromBuffer(&view);
    assert(numeric);
    assert(!_argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 0, &copied));
    assert(copied == 3 && numeric_destination[0] == -1 && numeric_destination[2] == 300 && numeric_destination[3] == 99);
    numeric_destination[0] = 77;
    assert(_argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 1, 8, 0, &copied) == -1);
    assert(copied == 0 && numeric_destination[0] == 77);
    assert(_argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 1, &copied) == -1);
    assert(numeric_destination[0] == 77);
    _argi_python_release(context, numeric);
    view.buf = numeric_source + 2;
    strides[0] = -(Py_ssize_t)sizeof(int64_t);
    numeric = PyMemoryView_FromBuffer(&view);
    assert(numeric && !_argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 0, &copied));
    assert(numeric_destination[0] == 300 && numeric_destination[1] == 2 && numeric_destination[2] == -1);
    _argi_python_release(context, numeric);
    uint16_t endian_marker = 1;
    view.format = *(uint8_t *)&endian_marker ? ">q" : "<q";
    numeric = PyMemoryView_FromBuffer(&view);
    assert(numeric && _argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 0, &copied) == -1);
    _argi_python_release(context, numeric);
    view.format = "q";
    view.ndim = 2;
    numeric = PyMemoryView_FromBuffer(&view);
    assert(numeric && _argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 0, &copied) == -1);
    _argi_python_release(context, numeric);
    view.ndim = 1;
    strides[0] = PY_SSIZE_T_MAX;
    numeric = PyMemoryView_FromBuffer(&view);
    assert(numeric && _argi_python_buffer_copy(context, numeric, (uint8_t *)numeric_destination, 4, 8, 0, &copied) == -1);
    _argi_python_release(context, numeric);
    assert(!_argi_python_numeric_storage(context, NULL, 3, 8));
    assert(!_argi_python_numeric_storage(context, (uint8_t *)numeric_source, UINTPTR_MAX, 8));
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
