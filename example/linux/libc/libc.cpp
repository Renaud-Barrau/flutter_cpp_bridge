#include <atomic>
#include <cstdint>
#include "flutter_cpp_bridge/service_helpers.h"

static std::atomic<int32_t> g_counter{0};

static void do_start() {
    g_counter.store(0, std::memory_order_relaxed);
}

static void do_stop() {
    g_counter.store(0, std::memory_order_relaxed);
}

FCB_EXPORT_STANDALONE(do_start, do_stop)

FCB_EXPORT int32_t increment() {
    return g_counter.fetch_add(1, std::memory_order_relaxed) + 1;
}
