/* Exercise the production adapter against deterministic thread outcomes.
   Renaming keeps the injected adapter separate from the installed runtime. */
#define _argi_thread_create probe_thread_create
#define _argi_thread_join probe_thread_join
#define _argi_thread_destroy probe_thread_destroy
#define _argi_task_create_buffers probe_task_create
#define _argi_task_create_inline_buffers probe_task_inline
#define _argi_task_join_result probe_task_result
#define _argi_task_result_block probe_task_block
#define _argi_task_take_owned_result probe_take_owned_result
#define _argi_task_release_storage probe_task_release_storage
#define _argi_task_destroy probe_task_destroy
#define _argi_execution_reclaim probe_reclaim
#define _argi_task_output_create probe_output_create
#define _argi_task_output_accepted probe_output_accepted
#define _argi_task_output_detach probe_output_detach
#define _argi_task_start_buffers probe_start_buffers
#define _argi_task_output_take probe_output_take
#define _argi_task_output_destroy probe_output_destroy
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
static argi_task_result_cleanup calculate(struct argi_execution_invocation invocation) {
    if (!invocation.identity || !invocation.input || !invocation.output ||
        invocation.input_size != sizeof(int) || invocation.output_size != sizeof(int) ||
        invocation.input_alignment != _Alignof(int) || invocation.output_alignment != _Alignof(int)) abort();
    ++calls;
    *(int *)invocation.output = *(int *)invocation.input * 2;
    return NULL;
}
static unsigned drops;
static void drop_result(uintptr_t storage) {
    if (*(int *)storage != 42) abort();
    ++drops;
}
static void other_drop(uintptr_t storage) { (void)storage; abort(); }
static argi_task_result_cleanup make_owned(struct argi_execution_invocation invocation) {
    calculate(invocation);
    return drop_result;
}
static void check_owned_result(void) {
    int input = 21;
    create_fails = 1;
    int before = calls;
    if (probe_task_create(make_owned, &input, sizeof(input), sizeof(int), _Alignof(int), _Alignof(int))) abort();
    if (calls != before || drops) abort();
    create_fails = 0;
    uintptr_t task = probe_task_create(make_owned, &input, sizeof(input), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task) abort();
    join_fails = 1;
    if (!probe_task_destroy(task) || drops) abort();
    join_fails = 0;
    destroy_fails = 1;
    if (!probe_task_destroy(task) || drops) abort();
    destroy_fails = 0;
    if (probe_task_destroy(task) || drops != 1) abort();
    task = probe_task_inline(make_owned, &input, sizeof(input), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || probe_task_result(task, sizeof(int)) || probe_task_block(task, 0).count) abort();
    if (!probe_task_release_storage(task) || drops != 1) abort();
    if (probe_take_owned_result(task, other_drop)) abort();
    uintptr_t owned = probe_take_owned_result(task, drop_result);
    if (!owned || probe_take_owned_result(task, drop_result) || probe_task_block(task, 0).count) abort();
    int moved = *(int *)owned;
    if (probe_task_release_storage(task) || drops != 1) abort();
    drop_result((uintptr_t)&moved);
    if (drops != 2) abort();
}
static void check_caller_output(void) {
    int input = 21;
    unsigned before = drops;
    uintptr_t slot = probe_output_create(make_owned);
    if (!slot || probe_output_accepted(slot, make_owned) || probe_output_take(slot, make_owned)) abort();
    create_fails = 1;
    if (probe_start_buffers(slot, 0, make_owned, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int))) abort();
    create_fails = 0;
    if (probe_output_accepted(slot, make_owned) || probe_output_take(slot, make_owned) || drops != before) abort();
    uintptr_t task = probe_start_buffers(slot, 1, make_owned, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || !probe_output_accepted(slot, make_owned) || probe_output_accepted(slot, calculate) ||
        !probe_output_destroy(slot) || probe_output_take(slot, make_owned)) abort();
    if (probe_task_result(task, sizeof(int)) || probe_take_owned_result(task, drop_result)) abort();
    if (probe_task_release_storage(task) || !probe_output_accepted(slot, make_owned) ||
        drops != before || !probe_output_destroy(slot)) abort();
    if (probe_output_take(slot, calculate)) abort();
    uintptr_t value = probe_output_take(slot, make_owned);
    if (!value || !probe_output_accepted(slot, make_owned) || probe_output_take(slot, make_owned)) abort();
    drop_result(value);
    if (probe_output_destroy(slot)) abort();
    if (drops != before + 1) abort();
}

static void check_detached_output(void) {
    int input = 21;
    uintptr_t slot = probe_output_create(calculate);
    uintptr_t unrelated = probe_output_create(calculate);
    if (!slot || !unrelated || !probe_output_detach(slot, 0, calculate)) abort();
    uintptr_t task = probe_start_buffers(slot, 0, calculate, &input, sizeof(input),
        sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || !probe_output_detach(slot, task, make_owned) ||
        !probe_output_detach(unrelated, task, calculate)) abort();
    if (probe_output_detach(slot, task, calculate) ||
        !probe_output_detach(slot, task, calculate) ||
        !probe_output_accepted(slot, calculate) || probe_output_take(slot, calculate)) abort();
    if (probe_output_destroy(slot) || probe_output_destroy(unrelated)) abort();
    uintptr_t value = probe_task_result(task, sizeof(int));
    if (!value || *(int *)value != 42 || probe_task_destroy(task)) abort();
}

static unsigned input_drops;
static void drop_input(int *input) {
    if (*input != 37) abort();
    free(input);
    ++input_drops;
}

static argi_task_result_cleanup consume_input(struct argi_execution_invocation invocation) {
    if (invocation.input_size != sizeof(int *) || invocation.output_size != 0) abort();
    drop_input(*(int **)invocation.input);
    return NULL;
}

static void check_owned_input(void) {
    /* The input buffer contains a copy of an owning representation. The
       caller retains its ownership when start fails. */
    int *owner = malloc(sizeof(*owner));
    if (!owner) abort();
    *owner = 37;
    create_fails = 1;
    if (probe_task_create(consume_input, &owner, sizeof(owner), 0, _Alignof(int *), 1)) abort();
    if (input_drops != 0) abort();
    drop_input(owner);
    create_fails = 0;

    /* A successful start delegates destruction to the callback, including
       when the worker runs before create returns or the task is discarded. */
    for (int mode = 0; mode < 3; ++mode) {
        unsigned before = input_drops;
        owner = malloc(sizeof(*owner));
        if (!owner) abort();
        *owner = 37;
        run_on_create = mode == 1;
        uintptr_t task = mode == 2
            ? probe_task_inline(consume_input, &owner, sizeof(owner), 0, _Alignof(int *), 1)
            : probe_task_create(consume_input, &owner, sizeof(owner), 0, _Alignof(int *), 1);
        if (!task || input_drops != before + (mode != 0)) abort();
        owner = NULL;
        if (probe_task_destroy(task) || input_drops != before + 1) abort();
    }
    run_on_create = 0;
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
    if (!output || *(int *)output != 42) abort();
    /* An unsuccessful read leaves the published result available for retry. */
    if (probe_task_block(task, sizeof(int)).count ||
        probe_task_result(task, sizeof(int)) != output ||
        probe_task_block(task, 0).count != sizeof(int) || joins != joined) abort();
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

    /* Discarding an accepted task must still run and join its callback. */
    run_on_create = 0;
    task = probe_task_create(calculate, &input, sizeof(int), sizeof(int), _Alignof(int), _Alignof(int));
    if (!task || calls != 3 || !pending_start) abort();
    if (probe_task_destroy(task) || calls != 4 || pending_start || joins != joined + 1) abort();
    check_owned_result();
    check_caller_output();
    check_detached_output();
    check_owned_input();
    return 0;
}
