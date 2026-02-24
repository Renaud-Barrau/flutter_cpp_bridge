#include <cstdio>

#define EXPORT extern "C" __attribute__((visibility("default")))

// StandaloneService requires these five symbols even if they are no-ops.

EXPORT
void start_service()
{
}

EXPORT
void stop_service()
{
}

EXPORT
void* get_next_message()
{
    return nullptr;
}

EXPORT
void free_message([[maybe_unused]] void* msg)
{
}

// No message queue: set_message_callback is a no-op.
EXPORT
void set_message_callback([[maybe_unused]] void (*cb)())
{
}

// Custom function looked up by AloneService.
EXPORT
void hello()
{
    printf("Hello from libalone!\n");
    fflush(stdout);
}
