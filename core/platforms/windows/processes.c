#include "../shared/process_arguments.h"
struct argi_child { HANDLE handle; DWORD code; int finished; };

/* Windows passes one UTF-16 command line. Quote every argument using the CRT
   backslash/quote rules, including empty arguments and trailing backslashes.
   Executable selection uses the explicit application path, never that string. */
static wchar_t *argi_process_wide(const char *text) {
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (!length) return NULL;
    wchar_t *wide = malloc((size_t)length * sizeof(wchar_t));
    if (!wide) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    if (wide && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, length)) {
        free(wide); return NULL;
    }
    return wide;
}
#include "process_command.h"
int32_t _argi_process_spawn(uintptr_t address, int32_t input, int32_t output, int32_t error,
                           uintptr_t *handle, uintptr_t *in, uintptr_t *out, uintptr_t *err) {
    struct argi_launch *launch = (struct argi_launch *)address;
    *handle = *in = *out = *err = 0;
    if (!launch || !launch->count) return -2;
    int32_t status = -1;
    wchar_t **args = calloc(launch->count, sizeof(wchar_t *));
    if (!args) return -3;
    wchar_t *command = NULL, *application = NULL;
    struct argi_child *child = NULL;
    HANDLE children[3] = { NULL, NULL, NULL }, parents[3] = { NULL, NULL, NULL };
    STARTUPINFOEXW startup = {0};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    int attribute_initialized = 0;
    for (size_t i = 0; i < launch->count; ++i) {
        args[i] = argi_process_wide(launch->arguments[i]);
        if (!args[i]) { status = GetLastError() == ERROR_NOT_ENOUGH_MEMORY ? -3 : -2; goto done; }
    }
    command = argi_process_command(args, launch->count);
    if (!command) { status = errno == ENOMEM ? -3 : -2; goto done; }
    /* SearchPath supplies normal Windows executable lookup without invoking a
       command interpreter. Explicit paths are also resolved by this API. */
    DWORD required = SearchPathW(NULL, args[0], L".exe", 0, NULL, NULL);
    if (!required || required >= 32767) goto done;
    application = malloc(((size_t)required + 1) * sizeof(wchar_t));
    if (!application) { status = -3; goto done; }
    DWORD resolved = SearchPathW(NULL, args[0], L".exe", required + 1, application, NULL);
    if (!resolved || resolved > required) goto done;
    int modes[3] = { input, output, error };
    DWORD standard[3] = { STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE };
    SECURITY_ATTRIBUTES security = { sizeof(security), NULL, TRUE };
    for (int i = 0; i < 3; ++i) {
        if (modes[i] < 0 || modes[i] > 2) { status = -2; goto done; }
        if (modes[i] == 1) {
            HANDLE read, write;
            if (!CreatePipe(&read, &write, &security, 0)) goto done;
            children[i] = i == 0 ? read : write;
            parents[i] = i == 0 ? write : read;
            if (!SetHandleInformation(parents[i], HANDLE_FLAG_INHERIT, 0)) goto done;
        } else if (modes[i] == 2) {
            children[i] = CreateFileW(L"NUL", i == 0 ? GENERIC_READ : GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
            if (children[i] == INVALID_HANDLE_VALUE) { children[i] = NULL; goto done; }
        } else {
            HANDLE original = GetStdHandle(standard[i]);
            if (original && original != INVALID_HANDLE_VALUE) {
                if (!DuplicateHandle(GetCurrentProcess(), original, GetCurrentProcess(),
                    &children[i], 0, TRUE, DUPLICATE_SAME_ACCESS)) goto done;
            } else {
                children[i] = CreateFileW(L"NUL", i == 0 ? GENERIC_READ : GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
                if (children[i] == INVALID_HANDLE_VALUE) { children[i] = NULL; goto done; }
            }
        }
    }
    SIZE_T attribute_size = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &attribute_size);
    startup.lpAttributeList = malloc(attribute_size);
    if (!startup.lpAttributeList) { status = -3; goto done; }
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &attribute_size)) goto done;
    attribute_initialized = 1;
    if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
        children, sizeof(children), NULL, NULL)) goto done;
    startup.StartupInfo.hStdInput = children[0];
    startup.StartupInfo.hStdOutput = children[1];
    startup.StartupInfo.hStdError = children[2];
    child = calloc(1, sizeof(*child));
    if (!child) { status = -3; goto done; }
    PROCESS_INFORMATION info;
    if (!CreateProcessW(application, command, NULL, NULL, TRUE, EXTENDED_STARTUPINFO_PRESENT,
        NULL, NULL, &startup.StartupInfo, &info)) goto done;
    CloseHandle(info.hThread);
    child->handle = info.hProcess;
    *handle = (uintptr_t)child;
    *in = (uintptr_t)parents[0];
    *out = (uintptr_t)parents[1];
    *err = (uintptr_t)parents[2];
    status = 0;
done:
    if (attribute_initialized) DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
    for (int i = 0; i < 3; ++i) {
        if (children[i]) CloseHandle(children[i]);
        if (status && parents[i]) CloseHandle(parents[i]);
    }
    if (status) free(child);
    for (size_t i = 0; i < launch->count; ++i) free(args[i]);
    free(args); free(command); free(application);
    return status;
}
int32_t _argi_process_wait(uintptr_t handle, uint32_t *code, uint32_t *signal) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child) return -1;
    if (!child->finished) {
        if (WaitForSingleObject(child->handle, INFINITE) != WAIT_OBJECT_0 ||
            !GetExitCodeProcess(child->handle, &child->code)) return -1;
        child->finished = 1;
    }
    *code = child->code; *signal = 0;
    return 0;
}
int32_t _argi_process_terminate(uintptr_t handle) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child) return -1;
    if (child->finished || WaitForSingleObject(child->handle, 0) == WAIT_OBJECT_0) return 0;
    if (TerminateProcess(child->handle, 1)) return 0;
    return WaitForSingleObject(child->handle, 0) == WAIT_OBJECT_0 ? 0 : -1;
}
void _argi_process_free(uintptr_t handle) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child) return;
    if (!child->finished && WaitForSingleObject(child->handle, 0) != WAIT_OBJECT_0) {
        if (TerminateProcess(child->handle, 1)) WaitForSingleObject(child->handle, INFINITE);
    }
    CloseHandle(child->handle);
    free(child);
}
int32_t _argi_process_stream_close(uintptr_t handle) {
    return handle && !CloseHandle((HANDLE)handle) ? -1 : 0;
}
int32_t _argi_process_stream_read(uintptr_t handle, uint8_t *byte) {
    DWORD count;
    if (!ReadFile((HANDLE)handle, byte, 1, &count, NULL))
        return GetLastError() == ERROR_BROKEN_PIPE ? 0 : -1;
    return (int32_t)count;
}
int32_t _argi_process_stream_write(uintptr_t handle, uint8_t byte) {
    DWORD count;
    return WriteFile((HANDLE)handle, &byte, 1, &count, NULL) && count == 1 ? 0 : -1;
}
