/* Exercise the production adapter against deterministic thread outcomes.
   Renaming keeps the injected adapter separate from the installed runtime. */
#define _argi_thread_create probe_thread_create
#define _argi_thread_join probe_thread_join
#define _argi_thread_destroy probe_thread_destroy
#define _argi_task_create_buffers probe_task_create
#define _argi_task_create_inline_buffers probe_task_inline
#define _argi_task_join_result probe_task_result
#define _argi_task_result_block probe_task_block
#define _argi_task_destroy probe_task_destroy
#define _argi_execution_reclaim probe_reclaim
#include "../../../../core/platforms/shared/task.c"

static argi_thread_start pending_start;
static void *pending_context;
static int create_fails, join_fails, destroy_fails, run_on_create;
static int calls, joins;
uintptr_t probe_thread_create(argi_thread_start start, void *context) {
    if (create_fails) return 0;
    pending_start = start;
    pending_context = context;
    if (run_on_create) { pending_start(pending_context); pending_start = NULL; }
    return 1;
}
int32_t probe_thread_join(uintptr_t handle) {
    if (handle != 1) abort();
    ++joins;
    if (join_fails) return -1;
    if (pending_start) { pending_start(pending_context); pending_start = NULL; }
    return 0;
}
int32_t probe_thread_destroy(uintptr_t handle) {
    if (handle != 1 || pending_start) abort();
    return destroy_fails ? -1 : 0;
}
static void calculate(struct argi_execution_invocation invocation) {
    if (!invocation.identity || !invocation.input || !invocation.output ||
        invocation.input_size != sizeof(int) || invocation.output_size != sizeof(int) ||
        invocation.input_alignment != _Alignof(int) || invocation.output_alignment != _Alignof(int)) abort();
    ++calls;
    *(int *)invocation.output = *(int *)invocation.input * 2;
}
int32_t execution_protocol_probe(void) {
    int input = 21;
    create_fails = 1;
    if (probe_task_create(calculate, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int)) || calls || joins) abort();
    create_fails = 0;
    uintptr_t task = probe_task_create(calculate, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || calls || !pending_start) abort();
    join_fails = 1;
    if (!probe_reclaim(task) || calls || !pending_start || probe_task_block(task, 0).count) abort();
    if (probe_task_result(task, sizeof(int)) || !probe_task_destroy(task) || calls) abort();
    join_fails = 0;
    if (probe_reclaim(task) || calls != 1 || pending_start) abort();
    int joined = joins;
    if (probe_reclaim(task) || joins != joined || calls != 1) abort();
    uintptr_t output = probe_task_result(task, sizeof(int));
    if (!output || *(int *)output != 42 || probe_task_result(task, sizeof(int))) abort();
    destroy_fails = 1;
    if (!probe_task_destroy(task) || *(int *)output != 42) abort();
    destroy_fails = 0;
    if (probe_task_destroy(task)) abort();
    run_on_create = 1;
    task = probe_task_create(calculate, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || calls != 2 || pending_start || probe_reclaim(task) || probe_task_destroy(task)) abort();
    joined = joins;
    task = probe_task_inline(calculate, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || calls != 3 || probe_reclaim(task) || probe_task_destroy(task) || joins != joined) abort();
    return 0;
}
