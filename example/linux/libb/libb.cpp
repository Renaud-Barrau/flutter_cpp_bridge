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

size_t nb_read_msg = 0;
std::mutex queue_mutex;  // Protect queue access
std::atomic<bool> stop_thread{false};  // Flag to stop the thread

static const std::array available = {"hello", "world", "this", "is", "me" };

EXPORT
void start_service()
{
    std::thread populate {[&]()
    {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<uint8_t> dis(0, available.size()-1);
        
        while (!stop_thread) {
            
            {
                std::lock_guard<std::mutex> lock(queue_mutex);
                ret.message = std::string(available[dis(gen)]);
            }
            
            // Wait 5 seconds
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
libb_message_t * get_next_message()
{
    std::lock_guard<std::mutex> lock(queue_mutex);
    return &ret;
}

EXPORT
void free_message([[maybe_unused]]libb_message_t * msg_to_free)
{
}

EXPORT
const char * get_text(libb_message_t* msg)
{
    if(msg != nullptr)
    {
        return ret.message.c_str() ;
    }
    return "null";
}