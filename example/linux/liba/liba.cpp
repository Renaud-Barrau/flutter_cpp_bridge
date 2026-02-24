#include <vector>
#include <cstdint>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>
#include <random>

#define EXPORT extern "C" __attribute__((visibility("default")))

struct liba_message_t
{
    uint8_t r;
    uint8_t g;
    uint8_t b;
};

std::vector<liba_message_t> queue;
std::mutex queue_mutex;
std::atomic<bool> stop_thread{false};

// Dart notification callback — set by set_message_callback, called from the
// worker thread whenever a new message is pushed onto the queue.
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
        std::uniform_int_distribution<uint8_t> dis(0, 255);

        while (!stop_thread) {
            liba_message_t msg;
            msg.r = dis(gen);
            msg.g = dis(gen);
            msg.b = dis(gen);

            {
                std::lock_guard<std::mutex> lock(queue_mutex);
                queue.push_back(msg);
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
liba_message_t* get_next_message()
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    return queue.empty() ? nullptr : &queue.front();
}

EXPORT
void free_message(liba_message_t* msg_to_free)
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    for (auto idx = 0; idx < static_cast<int>(queue.size()); ++idx)
    {
        if (&queue[idx] == msg_to_free)
        {
            queue.erase(queue.begin() + idx);
            break;
        }
    }
}

EXPORT
uint32_t get_hexa_color(liba_message_t* msg)
{
    return 0xFF << 24 | msg->r << 16 | msg->g << 8 | msg->b;
}
