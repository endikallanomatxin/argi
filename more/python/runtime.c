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
#if defined(ARGI_PYTHON_VERSION) && (PY_VERSION_HEX >> 16) != (ARGI_PYTHON_VERSION >> 16)
#error "Python development headers do not match the selected Python interpreter"
#endif
#ifdef Py_GIL_DISABLED
#error "more/python requires the standard GIL-enabled CPython build"
#endif

#ifndef ARGI_PYTHON_DEFAULT_EXECUTABLE
#define ARGI_PYTHON_DEFAULT_EXECUTABLE "python3"
#endif
#include "errors.h"

struct argi_python {
    unsigned long thread;
    struct argi_python_error *error;
};
static struct argi_python *active_python;
static int python_started;

static void native_error(struct argi_python *context, const char *text) {
    if (!context) return;
    replace_error(&context->error, make_error("BridgeError", sizeof("BridgeError") - 1,
        text, strlen(text), text, strlen(text)));
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
    /* Formatting can execute Python and fail itself. Capture native copies of
       all details before releasing the exception and clear secondary errors. */
    PyObject *exception = PyErr_GetRaisedException();
    if (!exception) { native_error(context, "Python operation failed without an exception"); return; }
    /* __str__ and traceback formatting can execute arbitrary Python. Keep the
       original type alive even if that code changes the exception's class. */
    PyObject *type_owner = Py_NewRef((PyObject *)Py_TYPE(exception));
    const char *type = ((PyTypeObject *)type_owner)->tp_name;
    PyObject *message = PyObject_Str(exception);
    if (!message) { PyErr_Clear(); message = PyUnicode_FromString("<exception message unavailable>"); }
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
        if (message) formatted = PyUnicode_FromFormat("%s: %U", type, message);
    }
    Py_ssize_t message_length = 0, traceback_length = 0;
    const char *message_text = message ? PyUnicode_AsUTF8AndSize(message, &message_length) : NULL;
    const char *traceback_text = formatted ? PyUnicode_AsUTF8AndSize(formatted, &traceback_length) : NULL;
    if (message_text && traceback_text) {
        replace_error(&context->error, make_error(type, strlen(type), message_text, (size_t)message_length,
            traceback_text, (size_t)traceback_length));
    } else native_error(context, "Cannot encode Python exception details");
    Py_XDECREF(message); Py_XDECREF(formatted); Py_XDECREF(lines); Py_XDECREF(traceback); Py_DECREF(exception); Py_DECREF(type_owner);
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
    if (python_started || active_python || Py_IsInitialized()) {
        set_initialization_error("An interpreter already exists or initialization has already been attempted");
        return 0;
    }
    /* Py_GetVersion is callable before initialization. Reject a mismatched
       embedding library before using version-specific configuration layouts. */
    char *version_end;
    unsigned long major = strtoul(Py_GetVersion(), &version_end, 10);
    unsigned long minor = *version_end == '.' ? strtoul(version_end + 1, NULL, 10) : 0;
    if (major != PY_MAJOR_VERSION || minor != PY_MINOR_VERSION) {
        set_initialization_error("Python headers and embedding library have different major/minor versions");
        return 0;
    }
    struct argi_python *context = calloc(1, sizeof(*context));
    if (!context) { replace_error(&initialization_failure, &memory_error); return 0; }
    char *program_text = c_text(context, program, program_length);
    char *home_text = c_text(context, home, home_length);
    if (!program_length) native_error(context, "Python program name must not be empty");
    if (!program_text || !home_text || !program_length) goto failed;
    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.install_signal_handlers = 0;
    config.parse_argv = 0;
    config.safe_path = 1;
    PyStatus status = PyConfig_SetBytesString(&config, &config.program_name,
        program_length == 7 && !memcmp(program, "python3", 7) ? ARGI_PYTHON_DEFAULT_EXECUTABLE : program_text);
    if (!PyStatus_Exception(status) && home_length)
        status = PyConfig_SetBytesString(&config, &config.home, home_text);
    if (!PyStatus_Exception(status)) {
        /* Even a failed initialization can leave extension/global runtime
           state behind. Do not attempt to initialize a second interpreter. */
        python_started = 1;
        status = Py_InitializeFromConfig(&config);
    }
    if (PyStatus_Exception(status)) {
        set_initialization_error(status.err_msg ? status.err_msg : "Python initialization requested exit");
    }
    PyConfig_Clear(&config);
    free(program_text); free(home_text);
    if (PyStatus_Exception(status)) {
        if (Py_IsInitialized()) { python_started = 1; Py_FinalizeEx(); }
        release_error(context->error); free(context);
        return 0;
    }
    python_started = 1;
    context->thread = PyThread_get_thread_ident();
    active_python = context;
    return (uintptr_t)context;
failed:
    replace_error(&initialization_failure, retain_error(context->error));
    free(program_text); free(home_text); release_error(context->error); free(context);
    return 0;
}
int32_t _argi_python_stop(uintptr_t address) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    int status = Py_FinalizeEx();
    active_python = NULL;
    release_error(context->error); free(context);
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
    return context->error ? context->error->lengths[2] : 0;
}
int32_t _argi_python_error_copy(uintptr_t address, uint8_t *destination, uintptr_t length) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    size_t size = context->error ? context->error->lengths[2] : 0;
    if (length < size) return -1;
    if (size) memcpy(destination, context->error->parts[2], size);
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

int32_t _argi_python_set_attribute(uintptr_t address, PyObject *object, const uint8_t *bytes, uintptr_t length, PyObject *value) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return -1;
    char *name = c_text(context, bytes, length);
    if (!name) return -1;
    int result = PyObject_SetAttrString(object, name, value);
    free(name);
    if (result) capture_error(context);
    return result;
}
PyObject *_argi_python_iterator(uintptr_t address, PyObject *object) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    PyObject *result = PyObject_GetIter(object);
    if (!result) capture_error(context);
    return result;
}
PyObject *_argi_python_next(uintptr_t address, PyObject *object, int32_t *exhausted) {
    struct argi_python *context = (struct argi_python *)address;
    *exhausted = 0;
    if (!guard(context)) return NULL;
    PyObject *result = PyIter_Next(object);
    if (!result) {
        if (PyErr_Occurred()) capture_error(context);
        else *exhausted = 1;
    }
    return result;
}

uintptr_t _argi_python_error_snapshot(uintptr_t address) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return (uintptr_t)&empty_error;
    return (uintptr_t)retain_error(context->error);
}
uintptr_t _argi_python_initialization_snapshot(void) {
    return (uintptr_t)retain_error(initialization_failure);
}
uintptr_t _argi_python_exception_clone(uintptr_t address) {
    return (uintptr_t)retain_error((struct argi_python_error *)address);
}
void _argi_python_exception_release(uintptr_t address) {
    release_error((struct argi_python_error *)address);
}
uintptr_t _argi_python_exception_size(uintptr_t address, int32_t part) {
    struct argi_python_error *error = (struct argi_python_error *)address;
    if (!error || part < 0 || part > 2) return 0;
    return error->lengths[part];
}
int32_t _argi_python_exception_copy(uintptr_t address, int32_t part, uint8_t *destination, uintptr_t length) {
    struct argi_python_error *error = (struct argi_python_error *)address;
    if (!error || part < 0 || part > 2 || length < error->lengths[part]) return -1;
    if (error->lengths[part]) memcpy(destination, error->parts[part], error->lengths[part]);
    return 0;
}

PyObject *_argi_python_numeric_storage(uintptr_t address, const uint8_t *source, uintptr_t count, uintptr_t itemsize) {
    struct argi_python *context = (struct argi_python *)address;
    if (!guard(context)) return NULL;
    if (!itemsize || itemsize > PY_SSIZE_T_MAX || count > PY_SSIZE_T_MAX / itemsize) {
        PyErr_SetString(PyExc_OverflowError, "Numeric input is too large"); capture_error(context); return NULL;
    }
    if (count && !source) { PyErr_SetString(PyExc_ValueError, "Numeric source has no storage"); capture_error(context); return NULL; }
    /* Python owns the copy; no exporter can retain an address in Argi storage. */
    PyObject *result = PyByteArray_FromStringAndSize((const char *)source, (Py_ssize_t)(count * itemsize));
    if (!result) capture_error(context);
    return result;
}
static int numeric_format_matches(const char *format, int32_t kind) {
    if (!format || !*format) return 0;
    uint16_t marker = 1;
    int little_endian = *(uint8_t *)&marker;
    if (*format == '<' || *format == '>' || *format == '!') {
        if ((*format == '<') != little_endian) return 0;
        format++;
    } else if (*format == '@' || *format == '=') format++;
    if (!*format || format[1]) return 0;
    if (kind == 0) return strchr("bhilqn", *format) != NULL;
    if (kind == 1) return strchr("BHILQN", *format) != NULL;
    if (kind == 2) return *format == 'f' || *format == 'd';
    return 0;
}
int32_t _argi_python_buffer_copy(uintptr_t address, PyObject *object, uint8_t *destination,
        uintptr_t capacity, uintptr_t itemsize, int32_t kind, uintptr_t *copied) {
    struct argi_python *context = (struct argi_python *)address;
    *copied = 0;
    if (!guard(context)) return -1;
    Py_buffer buffer;
    if (PyObject_GetBuffer(object, &buffer, PyBUF_STRIDES | PyBUF_FORMAT)) { capture_error(context); return -1; }
    int result = -1;
    if (buffer.ndim != 1 || !buffer.shape || buffer.shape[0] < 0 ||
        buffer.itemsize <= 0 || (uintptr_t)buffer.itemsize != itemsize ||
        !numeric_format_matches(buffer.format, kind) ||
        (buffer.suboffsets && buffer.suboffsets[0] >= 0)) {
        PyErr_SetString(PyExc_TypeError, "Expected a one-dimensional buffer with the matching native numeric type");
        goto finished;
    }
    Py_ssize_t count = buffer.shape[0];
    if (count > PY_SSIZE_T_MAX / buffer.itemsize || buffer.len != count * buffer.itemsize) {
        PyErr_SetString(PyExc_BufferError, "Invalid numeric buffer extent"); goto finished;
    }
    if ((uintptr_t)count > capacity) {
        PyErr_SetString(PyExc_BufferError, "Numeric destination is too small"); goto finished;
    }
    Py_ssize_t stride = buffer.strides ? buffer.strides[0] : buffer.itemsize;
    if (count > 1 && ((stride > 0 && stride > PY_SSIZE_T_MAX / (count - 1)) ||
        (stride < 0 && stride < PY_SSIZE_T_MIN / (count - 1)))) {
        PyErr_SetString(PyExc_BufferError, "Numeric buffer stride is too large"); goto finished;
    }
    if (count && !destination) { PyErr_SetString(PyExc_ValueError, "Numeric destination has no storage"); goto finished; }
    if (count && !buffer.buf) { PyErr_SetString(PyExc_BufferError, "Numeric buffer has no storage"); goto finished; }
    /* Metadata is fully checked before touching initialized destination slots.
       Strided/reversed inputs follow the exporter's logical element order. */
    if (count && stride == buffer.itemsize) {
        memcpy(destination, buffer.buf, (size_t)buffer.len);
    } else {
        for (Py_ssize_t i = 0; i < count; i++)
            memcpy(destination + (size_t)i * itemsize, (uint8_t *)buffer.buf + i * stride, itemsize);
    }
    *copied = (uintptr_t)count;
    result = 0;
finished:
    if (result) capture_error(context);
    PyBuffer_Release(&buffer);
    return result;
}
