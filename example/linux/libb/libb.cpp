#include <array>
#include <string>
#include <vector>
#include <cstdint>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>
#include <random>

#define EXPORT extern "C" __attribute__((visibility("default")))

struct libb_message_t
{
    std::string message;
};

libb_message_t ret;
// true when a new message has been written and not yet consumed by Dart.
static bool g_message_ready = false;

std::mutex queue_mutex;
std::atomic<bool> stop_thread{false};

static const std::array available = {"hello", "world", "this", "is", "me"};

// Dart notification callback — set by set_message_callback, called from the
// worker thread whenever the message is updated.
static void (*g_callback)() = nullptr;

EXPORT
void set_message_callback(void (*cb)())
{
    g_callback = cb;
}

EXPORT
void start_service()
{
    std::thread populate {[&]()
    {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<uint8_t> dis(0, available.size() - 1);

        while (!stop_thread) {
            {
                std::lock_guard<std::mutex> lock(queue_mutex);
                ret.message = std::string(available[dis(gen)]);
                g_message_ready = true;
            }

            // Notify Dart that a new message is available.
            if (g_callback) g_callback();

            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    }};
    populate.detach();
}

EXPORT
void stop_service()
{
    stop_thread = true;
}

EXPORT
libb_message_t* get_next_message()
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    return g_message_ready ? &ret : nullptr;
}

EXPORT
void free_message([[maybe_unused]] libb_message_t* msg_to_free)
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    g_message_ready = false;
}

EXPORT
const char* get_text(libb_message_t* msg)
{
    if (msg != nullptr)
    {
        return ret.message.c_str();
    }
    return "null";
}
