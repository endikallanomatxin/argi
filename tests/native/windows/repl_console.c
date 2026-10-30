#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Drain concurrently: closing a pseudoconsole can itself produce output. */
static SRWLOCK lock = SRWLOCK_INIT;
static char transcript[1024 * 1024];
static size_t used;
static DWORD WINAPI drain(void *pipe) {
    char bytes[4096];
    DWORD count;
    while (ReadFile((HANDLE)pipe, bytes, sizeof bytes, &count, NULL) && count) {
        AcquireSRWLockExclusive(&lock);
        size_t available = sizeof transcript - used - 1;
        size_t copied = count < available ? count : available;
        memcpy(transcript + used, bytes, copied);
        used += copied;
        transcript[used] = 0;
        ReleaseSRWLockExclusive(&lock);
    }
    return 0;
}

static int await_text(HANDLE process, const char *text) {
    ULONGLONG deadline = GetTickCount64() + 30000;
    do {
        AcquireSRWLockShared(&lock);
        int found = strstr(transcript, text) != NULL;
        ReleaseSRWLockShared(&lock);
        if (found) return 1;
        if (WaitForSingleObject(process, 0) != WAIT_TIMEOUT) {
            DWORD code = 0;
            GetExitCodeProcess(process, &code);
            fprintf(stderr, "REPL exited before the prompt/result (code 0x%08lx).\n", code);
            break;
        }
        Sleep(10);
    } while (GetTickCount64() < deadline);
    fprintf(stderr, "Missing console output: %s\n", text);
    return 0;
}

static int send_text(HANDLE input, const char *text) {
    DWORD count, length = (DWORD)strlen(text);
    return WriteFile(input, text, length, &count, NULL) && count == length;
}

static BOOL start_client(const wchar_t *executable, wchar_t *command,
                         STARTUPINFOEXW *startup, PROCESS_INFORMATION *process) {
    const DWORD streams[] = {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE};
    HANDLE saved[3];
    for (size_t i = 0; i < 3; ++i) saved[i] = GetStdHandle(streams[i]);
    BOOL created = FALSE;
    DWORD error;
    /* The CI shell redirects these streams. Do not let process creation
       duplicate its EOF input pipe into the pseudoconsole client. */
    for (size_t i = 0; i < 3; ++i)
        if (!SetStdHandle(streams[i], NULL)) goto restore;
    created = CreateProcessW(executable, command, NULL, NULL, FALSE,
            EXTENDED_STARTUPINFO_PRESENT, NULL, NULL,
            &startup->StartupInfo, process);
restore:
    error = GetLastError();
    for (size_t i = 0; i < 3; ++i) SetStdHandle(streams[i], saved[i]);
    SetLastError(error);
    return created;
}

int wmain(int argc, wchar_t **argv) {
    HANDLE input_read = NULL, input_write = NULL;
    HANDLE output_read = NULL, output_write = NULL, reader = NULL;
    HPCON console = NULL;
    PROCESS_INFORMATION process = {0};
    STARTUPINFOEXW startup = {0};
    SIZE_T attribute_bytes = 0;
    int initialized = 0, result = 1;
    wchar_t *command = NULL;
    if (argc != 2 && !(argc == 3 && wcscmp(argv[2], L"--eof") == 0)) return 2;
    if (!CreatePipe(&input_read, &input_write, NULL, 0) ||
        !CreatePipe(&output_read, &output_write, NULL, 0)) goto cleanup;
    if (FAILED(CreatePseudoConsole((COORD){24, 24}, input_read, output_write,
                                  0, &console))) goto cleanup;
    CloseHandle(input_read); input_read = NULL;
    CloseHandle(output_write); output_write = NULL;
    reader = CreateThread(NULL, 0, drain, output_read, 0, NULL);
    if (!reader) goto cleanup;
    InitializeProcThreadAttributeList(NULL, 1, 0, &attribute_bytes);
    startup.lpAttributeList = malloc(attribute_bytes);
    if (!startup.lpAttributeList) goto cleanup;
    if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0,
                                           &attribute_bytes)) goto cleanup;
    initialized = 1;
    if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console, sizeof console,
            NULL, NULL)) goto cleanup;
    size_t capacity = wcslen(argv[1]) + 64;
    command = calloc(capacity, sizeof *command);
    if (!command) goto cleanup;
    swprintf(command, capacity, L"\"%ls\" repl --vm-instructions 1000000000", argv[1]);
    startup.StartupInfo.cb = sizeof startup;
    /* A shell may ignore Ctrl-C; the execution command must still opt in to
       cancellation even when this process attribute is inherited. */
    if (!SetConsoleCtrlHandler(NULL, TRUE)) goto cleanup;
    if (!start_client(argv[1], command, &startup, &process)) goto cleanup;
    /* ConPTY can encode the trailing blank as cursor movement. */
    if (!await_text(process.hProcess, ">>>")) goto cleanup;
    /* Home, right and Delete must edit complete UTF-8 scalars. */
    if (!send_text(input_write,
            "\"\xe7\x95\x8c" "a\xf0\x9f\x99\x82\"\x1b[H\x1b[C\x1b[3~\r") ||
        !await_text(process.hProcess, "_0 = \"a\xf0\x9f\x99\x82\"")) goto cleanup;
    if (!send_text(input_write, "\x1b[A\r") ||
        !await_text(process.hProcess, "_1 = \"a\xf0\x9f\x99\x82\"")) goto cleanup;
    if (!send_text(input_write, "discarded\x03") ||
        !await_text(process.hProcess, "^C")) goto cleanup;
    if (!send_text(input_write, "42\r") ||
        !await_text(process.hProcess, "_2 = 42")) goto cleanup;
    if (!send_text(input_write,
            "answer := () -> (.result: Int32) {\rresult = 43\r}\ranswer()\r") ||
        !await_text(process.hProcess, "_3 = 43")) goto cleanup;
    if (FAILED(ResizePseudoConsole(console, (COORD){160, 24}))) goto cleanup;
    if (!send_text(input_write,
            "if true {\runwrap_or_abort(.value = print(\"RUNTIME_READY\\n\"))\runwrap_or_abort(.value = flush(.self = writer))\rwhile true {}\r}\r") ||
        !await_text(process.hProcess, "RUNTIME_READY\r\n")) goto cleanup;
    if (!send_text(input_write, "\x03") ||
        !await_text(process.hProcess, "ExecutionCancelled")) goto cleanup;
    if (!send_text(input_write, ":reset\r44\r") ||
        !await_text(process.hProcess, "_0 = 44")) goto cleanup;
    if (!send_text(input_write, argc == 3 ? "\x04" : ":quit\r") ||
        WaitForSingleObject(process.hProcess, 30000) != WAIT_OBJECT_0) goto cleanup;
    DWORD exit_code;
    if (!GetExitCodeProcess(process.hProcess, &exit_code) || exit_code) goto cleanup;
    result = 0;
cleanup:
    if (result) fprintf(stderr, "Console probe failed (Windows error %lu).\n", GetLastError());
    if (process.hProcess) {
        if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
            TerminateProcess(process.hProcess, 1);
            WaitForSingleObject(process.hProcess, 30000);
        }
        CloseHandle(process.hProcess);
        CloseHandle(process.hThread);
    }
    if (input_write) CloseHandle(input_write);
    if (console) ClosePseudoConsole(console);
    if (output_write) CloseHandle(output_write);
    if (reader) { WaitForSingleObject(reader, INFINITE); CloseHandle(reader); }
    if (result) fputs(transcript, stderr);
    if (input_read) CloseHandle(input_read);
    if (output_read) CloseHandle(output_read);
    if (initialized) DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
    free(command);
    return result;
}
