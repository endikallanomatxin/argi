/* Resolve the system provider without adding a consumer link dependency. */
int32_t _argi_system_entropy(unsigned char *bytes, uintptr_t length) {
    if (!length) return 0;
    if (!bytes || length > 256) return -1;
    HMODULE module = LoadLibraryExW(L"bcrypt.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) return -1;
    typedef LONG (WINAPI *generate_function)(void *, unsigned char *, ULONG, ULONG);
    FARPROC symbol = GetProcAddress(module, "BCryptGenRandom");
    generate_function generate = NULL;
    _Static_assert(sizeof(generate) == sizeof(symbol), "Windows function address width");
    memcpy(&generate, &symbol, sizeof(generate));
    LONG status = generate ? generate(NULL, bytes, (ULONG)length, 2) : -1;
    FreeLibrary(module);
    return status == 0 ? 0 : -1;
}
