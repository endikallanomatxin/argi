/* Optional CPython embedding boundary. Compile this file against the Python
   development headers and link the matching embedding library explicitly. */
#include <Python.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#if PY_VERSION_HEX < 0x030C0000
#error "more/python requires CPython 3.12 or newer"
#endif
#ifdef Py_GIL_DISABLED
#error "more/python requires the standard GIL-enabled CPython build"
#endif

struct argi_python {
    unsigned long thread;
    char *error;
    size_t error_length;
};
static struct argi_python *active_python;
static int python_started;

static void native_error(struct argi_python *context, const char *text) {
    if (!context) return;
    size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (!copy) return;
    memcpy(copy, text, length + 1);
    free(context->error);
    context->error = copy;
    context->error_length = length;
}
static int guard(struct argi_python *context) {
    if (!context || context != active_python || !Py_IsInitialized()) return 0;
    if (context->thread != PyThread_get_thread_ident()) {
        native_error(context, "Python operations require the interpreter's creating thread");
        return 0;
    }
    return 1;
}
static void capture_error(struct argi_python *context) {
    /* Preserve the original exception while traceback formatting may itself
       fail. No Python error indicator escapes back to the Argi caller. */
    PyObject *exception = PyErr_GetRaisedException();
    if (!exception) { native_error(context, "Python operation failed without an exception"); return; }
    PyObject *traceback = PyImport_ImportModule("traceback"), *lines = NULL, *formatted = NULL;
    if (traceback) {
        lines = PyObject_CallMethod(traceback, "format_exception", "O", exception);
        if (lines) {
            PyObject *separator = PyUnicode_FromString("");
            if (separator) { formatted = PyUnicode_Join(separator, lines); Py_DECREF(separator); }
        }
    }
    if (!formatted) {
        PyErr_Clear();
        PyObject *value = PyObject_Str(exception);
        if (value) {
            formatted = PyUnicode_FromFormat("%s: %U", Py_TYPE(exception)->tp_name, value);
            Py_DECREF(value);
        }
    }
    if (formatted) {
        Py_ssize_t length;
        const char *bytes = PyUnicode_AsUTF8AndSize(formatted, &length);
        if (bytes) {
            char *copy = malloc((size_t)length + 1);
            if (copy) {
                memcpy(copy, bytes, (size_t)length);
                copy[length] = 0;
                free(context->error);
                context->error = copy;
                context->error_length = (size_t)length;
            } else native_error(context, "Cannot allocate Python exception text");
        } else native_error(context, "Cannot encode Python exception text");
    } else native_error(context, "Cannot format Python exception");
    Py_XDECREF(formatted); Py_XDECREF(lines); Py_XDECREF(traceback); Py_DECREF(exception);
    PyErr_Clear();
}
static char *c_text(struct argi_python *context, const uint8_t *bytes, uintptr_t length) {
    if (length == SIZE_MAX || memchr(bytes, 0, length)) {
        native_error(context, "Name or interpreter path contains an embedded NUL or is too large");
        return NULL;
    }
    char *text = malloc((size_t)length + 1);
    if (!text) { native_error(context, "Cannot allocate Python call input"); return NULL; }
    memcpy(text, bytes, length); text[length] = 0;
    return text;
}
uintptr_t _argi_python_start(const uint8_t *program, uintptr_t program_length,
                             const uint8_t *home, uintptr_t home_length) {
    /* Restart is deliberately unsupported: native extension modules can keep
       process-global state that is not safely reset by Py_FinalizeEx. */
    if (python_started || active_python || Py_IsInitialized()) return 0;
    struct argi_python *context = calloc(1, sizeof(*context));
    if (!context) return 0;
    char *program_text = c_text(context, program, program_length);
    char *home_text = c_text(context, home, home_length);
    if (!program_text || !home_text || !program_length) goto failed;
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.install_signal_handlers = 0;
    config.parse_argv = 0;
    config.safe_path = 1;
    PyStatus status = PyConfig_SetBytesString(&config, &config.program_name, program_text);
    if (!PyStatus_Exception(status) && home_length)
        status = PyConfig_SetBytesString(&config, &config.home, home_text);
    if (!PyStatus_Exception(status)) {
        /* Even a failed initialization can leave extension/global runtime
           state behind. Do not attempt to initialize a second interpreter. */
        python_started = 1;
        status = Py_InitializeFromConfig(&config);
    }
    PyConfig_Clear(&config);
    free(program_text); free(home_text);
    if (PyStatus_Exception(status)) {
        if (Py_IsInitialized()) { python_started = 1; Py_FinalizeEx(); }
        free(context->error); free(context);
        return 0;
    }
    python_started = 1;
    context->thread = PyThread_get_thread_ident();
    active_python = context;
    return (uintptr_t)context;
failed:
    free(program_text); free(home_text); free(context->error); free(context);
    return 0;
}
int32_t _argi_python_stop(uintptr_t address) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    int status = Py_FinalizeEx();
    active_python = NULL;
    free(context->error); free(context);
    return status;
}
void _argi_python_release(uintptr_t address, PyObject *object) {
    struct argi_python *context = (struct argi_python *)address;
    if (guard(context)) Py_XDECREF(object);
}
PyObject *_argi_python_clone(uintptr_t address, PyObject *object) {
    if (!guard((struct argi_python *)address) || !object) return NULL;
    return Py_NewRef(object);
}
PyObject *_argi_python_import(uintptr_t address, const uint8_t *bytes, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    char *name = c_text(context, bytes, length);
    if (!name) return NULL;
    PyObject *result = PyImport_ImportModule(name);
    free(name);
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_attribute(uintptr_t address, PyObject *object, const uint8_t *bytes, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context) || !object) return NULL;
    char *name = c_text(context, bytes, length);
    if (!name) return NULL;
    PyObject *result = PyObject_GetAttrString(object, name);
    free(name);
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_string(uintptr_t address, const uint8_t *bytes, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    if (length > PY_SSIZE_T_MAX) { native_error(context, "Python string is too large"); return NULL; }
    PyObject *result = PyUnicode_DecodeUTF8((const char *)bytes, (Py_ssize_t)length, "strict");
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_bytes(uintptr_t address, const uint8_t *bytes, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    if (length > PY_SSIZE_T_MAX) { native_error(context, "Python bytes are too large"); return NULL; }
    PyObject *result = PyBytes_FromStringAndSize((const char *)bytes, (Py_ssize_t)length);
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_scalar(uintptr_t address, int32_t kind, int64_t signed_value, uint64_t unsigned_value, double float_value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    PyObject *result;
    switch (kind) {
        case 0: result = Py_NewRef(Py_None); break;
        case 1: result = PyBool_FromLong(signed_value != 0); break;
        case 2: result = PyLong_FromLongLong(signed_value); break;
        case 3: result = PyLong_FromUnsignedLongLong(unsigned_value); break;
        case 4: result = PyFloat_FromDouble(float_value); break;
        case 5: result = PyList_New(0); break;
        case 6: result = PyDict_New(); break;
        default: PyErr_SetString(PyExc_ValueError, "Unknown Argi Python scalar kind"); result = NULL;
    }
    if (!result) capture_error(context);
    return result;
}
int32_t _argi_python_int64(uintptr_t address, PyObject *object, int64_t *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (!PyLong_Check(object) || PyBool_Check(object)) { PyErr_SetString(PyExc_TypeError, "Expected a Python integer"); goto failed; }
    *value = PyLong_AsLongLong(object);
    if (PyErr_Occurred()) goto failed;
    return 0;
failed: capture_error(context); return -1;
}
int32_t _argi_python_uint64(uintptr_t address, PyObject *object, uint64_t *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (!PyLong_Check(object) || PyBool_Check(object)) { PyErr_SetString(PyExc_TypeError, "Expected a Python integer"); goto failed; }
    *value = PyLong_AsUnsignedLongLong(object);
    if (PyErr_Occurred()) goto failed;
    return 0;
failed: capture_error(context); return -1;
}
int32_t _argi_python_float64(uintptr_t address, PyObject *object, double *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (!PyFloat_Check(object)) { PyErr_SetString(PyExc_TypeError, "Expected a Python float"); capture_error(context); return -1; }
    *value = PyFloat_AS_DOUBLE(object);
    return 0;
}
int32_t _argi_python_bool(uintptr_t address, PyObject *object) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (!PyBool_Check(object)) { PyErr_SetString(PyExc_TypeError, "Expected a Python bool"); capture_error(context); return -1; }
    return object == Py_True;
}
int32_t _argi_python_is_none(uintptr_t address, PyObject *object) {
    if (!guard((struct argi_python *)address)) return -1;
    return object == Py_None;
}
int32_t _argi_python_size(uintptr_t address, PyObject *object, uintptr_t *length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    Py_ssize_t size = PyObject_Size(object);
    if (size < 0) { capture_error(context); return -1; }
    *length = (uintptr_t)size;
    return 0;
}
PyObject *_argi_python_get_item(uintptr_t address, PyObject *object, PyObject *key) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    PyObject *result = PyObject_GetItem(object, key);
    if (!result) capture_error(context);
    return result;
}
int32_t _argi_python_set_item(uintptr_t address, PyObject *object, PyObject *key, PyObject *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (PyObject_SetItem(object, key, value)) { capture_error(context); return -1; }
    return 0;
}
int32_t _argi_python_append(uintptr_t address, PyObject *object, PyObject *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (!PyList_Check(object)) { PyErr_SetString(PyExc_TypeError, "Expected a Python list"); capture_error(context); return -1; }
    if (PyList_Append(object, value)) { capture_error(context); return -1; }
    return 0;
}
PyObject *_argi_python_tuple(uintptr_t address, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    if (length > PY_SSIZE_T_MAX) { native_error(context, "Too many Python arguments"); return NULL; }
    PyObject *result = PyTuple_New((Py_ssize_t)length);
    if (!result) capture_error(context);
    return result;
}
int32_t _argi_python_tuple_set(uintptr_t address, PyObject *tuple, uintptr_t index, PyObject *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    if (index > PY_SSIZE_T_MAX) return -1;
    /* PyTuple_SetItem steals the new reference, including its error path. */
    if (PyTuple_SetItem(tuple, (Py_ssize_t)index, Py_NewRef(value))) { capture_error(context); return -1; }
    return 0;
}
PyObject *_argi_python_call(uintptr_t address, PyObject *callable, PyObject *args, PyObject *keywords) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    if (!PyTuple_Check(args)) { PyErr_SetString(PyExc_TypeError, "Positional arguments must be a Python tuple"); capture_error(context); return NULL; }
    if (keywords && !PyDict_Check(keywords)) { PyErr_SetString(PyExc_TypeError, "Keywords must be a Python dict"); capture_error(context); return NULL; }
    PyObject *result = PyObject_Call(callable, args, keywords);
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_repr(uintptr_t address, PyObject *object) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    PyObject *result = PyObject_Repr(object);
    if (!result) capture_error(context);
    return result;
}
static const char *object_bytes(PyObject *object, int32_t kind, Py_ssize_t *size) {
    if (kind == 0) return PyUnicode_AsUTF8AndSize(object, size);
    char *bytes;
    if (PyBytes_AsStringAndSize(object, &bytes, size)) return NULL;
    return bytes;
}
int32_t _argi_python_text_size(uintptr_t address, PyObject *object, int32_t kind, uintptr_t *length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    Py_ssize_t size;
    if (!object_bytes(object, kind, &size)) { capture_error(context); return -1; }
    *length = (uintptr_t)size;
    return 0;
}
int32_t _argi_python_text_copy(uintptr_t address, PyObject *object, int32_t kind, uint8_t *destination, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    Py_ssize_t size;
    const char *bytes = object_bytes(object, kind, &size);
    if (!bytes) { capture_error(context); return -1; }
    if ((uintptr_t)size > length) { PyErr_SetString(PyExc_BufferError, "Destination is too small"); capture_error(context); return -1; }
    if (size) memcpy(destination, bytes, (size_t)size);
    return 0;
}
uintptr_t _argi_python_error_size(uintptr_t address) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return 0;
    return context->error_length;
}
int32_t _argi_python_error_copy(uintptr_t address, uint8_t *destination, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context) || length < context->error_length) return -1;
    if (context->error_length) memcpy(destination, context->error, context->error_length);
    return 0;
}

PyObject *_argi_python_float32(uintptr_t address, float value) {
    return _argi_python_scalar(address, 4, 0, 0, (double)value);
}
PyObject *_argi_python_as_tuple(uintptr_t address, PyObject *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    PyObject *result = PySequence_Tuple(value);
    if (!result) capture_error(context);
    return result;
}
