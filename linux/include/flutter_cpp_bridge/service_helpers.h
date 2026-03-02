// flutter_cpp_bridge/service_helpers.h
//
// Header-only C++ helpers for implementing flutter_cpp_bridge services.
//
// Instead of writing the full 5-symbol boilerplate by hand, include this
// header, declare a global service instance (fcb::Queue<T> or
// fcb::CurrentValue<T>), write only your worker body, then call one macro
// to generate all five mandatory exported symbols.
//
// Requirements: C++17 or later.
//
// ─── Minimal pooled service (queue) ─────────────────────────────────────────
//
//   #include "flutter_cpp_bridge/service_helpers.h"
//
//   struct my_msg_t { int value; };
//   static fcb::Queue<my_msg_t> g_svc;
//
//   static void worker(fcb::Queue<my_msg_t>& svc) {
//       int i = 0;
//       while (!svc.stopped()) {
//           svc.push({i++});
//           std::this_thread::sleep_for(std::chrono::seconds(1));
//       }
//   }
//
//   FCB_EXPORT_SYMBOLS(g_svc, worker)
//
//   FCB_EXPORT int get_value(my_msg_t* msg) { return msg->value; }
//
// ─── Standalone service (no queue) ──────────────────────────────────────────
//
//   #include "flutter_cpp_bridge/service_helpers.h"
//   #include <cstdio>
//
//   FCB_EXPORT_STANDALONE_NOOP()
//
//   FCB_EXPORT void hello() { printf("Hello!\n"); fflush(stdout); }
//

#pragma once
#include <atomic>
#include <deque>
#include <mutex>
#include <thread>

// Visibility macro reused for all exported symbols (mandatory and extra).
#define FCB_EXPORT extern "C" __attribute__((visibility("default")))

namespace fcb {

// ── Shared base ──────────────────────────────────────────────────────────────
struct ServiceBase {
    std::mutex           mtx;
    std::atomic<bool>    stop_flag{false};
    void               (*notify_cb)() = nullptr;

    bool stopped() const noexcept {
        return stop_flag.load(std::memory_order_relaxed);
    }
    void notify() const noexcept { if (notify_cb) notify_cb(); }
};

// ── Queue variant ────────────────────────────────────────────────────────────
// Worker calls push(); Dart drains one message at a time (FIFO).
//
// std::deque is intentional: push_back() never invalidates references to
// existing elements, so Dart can safely hold a pointer to &front() while
// the worker is pushing new messages at the back.
template<typename T>
struct Queue : ServiceBase {
    std::deque<T> _q;

    void push(T msg) {
        { std::lock_guard<std::mutex> lk(mtx); _q.push_back(std::move(msg)); }
        notify();
    }

    void* next() noexcept {
        std::lock_guard<std::mutex> lk(mtx);
        return _q.empty() ? nullptr : static_cast<void*>(&_q.front());
    }

    void release(void* p) noexcept {
        std::lock_guard<std::mutex> lk(mtx);
        auto* typed = static_cast<T*>(p);
        for (auto it = _q.begin(); it != _q.end(); ++it)
            if (&(*it) == typed) { _q.erase(it); return; }
    }
};

// ── Current-value variant ────────────────────────────────────────────────────
// Worker calls set(); Dart reads the latest value once then releases it.
// Only one message is live at a time; _ready acts as the nullptr sentinel
// so get_next_message() correctly returns nullptr after consumption.
template<typename T>
struct CurrentValue : ServiceBase {
    T    _val{};
    bool _ready = false;

    void set(T val) {
        { std::lock_guard<std::mutex> lk(mtx); _val = std::move(val); _ready = true; }
        notify();
    }

    void* next() noexcept {
        std::lock_guard<std::mutex> lk(mtx);
        return _ready ? static_cast<void*>(&_val) : nullptr;
    }

    void release(void*) noexcept {
        std::lock_guard<std::mutex> lk(mtx);
        _ready = false;
    }
};

} // namespace fcb

// ── FCB_EXPORT_SYMBOLS ───────────────────────────────────────────────────────
// Generates the five mandatory C-linkage symbols for a pooled service.
//
// Parameters:
//   svc        — name of a global fcb::Queue<T> or fcb::CurrentValue<T>
//   worker_fn  — name of a function with signature:
//                  void worker_fn(decltype(svc)& svc)
//
// The worker runs on a detached thread; svc.stopped() returns true once
// stop_service() is called.
//
#define FCB_EXPORT_SYMBOLS(svc, worker_fn)                                          \
    FCB_EXPORT void  start_service() {                                              \
        (svc).stop_flag.store(false, std::memory_order_relaxed);                    \
        std::thread([&s = (svc)]() { worker_fn(s); }).detach();                     \
    }                                                                               \
    FCB_EXPORT void  stop_service()  {                                              \
        (svc).stop_flag.store(true, std::memory_order_relaxed);                     \
    }                                                                               \
    FCB_EXPORT void* get_next_message()        { return (svc).next();    }          \
    FCB_EXPORT void  free_message(void* p)     { (svc).release(p);       }          \
    FCB_EXPORT void  set_message_callback(void (*cb)()) { (svc).notify_cb = cb; }

// ── FCB_EXPORT_STANDALONE_NOOP ───────────────────────────────────────────────
// Generates five no-op mandatory symbols for a standalone service (command
// sink, logger, …) that has no message queue.
//
#define FCB_EXPORT_STANDALONE_NOOP()                                                \
    FCB_EXPORT void  start_service() {}                                             \
    FCB_EXPORT void  stop_service()  {}                                             \
    FCB_EXPORT void* get_next_message()                     { return nullptr; }     \
    FCB_EXPORT void  free_message([[maybe_unused]] void* p) {}                      \
    FCB_EXPORT void  set_message_callback([[maybe_unused]] void (*cb)()) {}

// ── FCB_EXPORT_STANDALONE ────────────────────────────────────────────────────
// Like FCB_EXPORT_STANDALONE_NOOP but delegates start/stop to named functions.
//
// Parameters:
//   start_fn / stop_fn — names of void() functions to call from
//                        start_service() / stop_service().
//
#define FCB_EXPORT_STANDALONE(start_fn, stop_fn)                                    \
    FCB_EXPORT void  start_service() { (start_fn)(); }                              \
    FCB_EXPORT void  stop_service()  { (stop_fn)();  }                              \
    FCB_EXPORT void* get_next_message()                     { return nullptr; }     \
    FCB_EXPORT void  free_message([[maybe_unused]] void* p) {}                      \
    FCB_EXPORT void  set_message_callback([[maybe_unused]] void (*cb)()) {}
