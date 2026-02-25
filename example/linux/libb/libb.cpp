#include <array>
#include <chrono>
#include <random>
#include <string>
#include "flutter_cpp_bridge/service_helpers.h"

struct libb_message_t
{
    std::string message;
};

static fcb::CurrentValue<libb_message_t> g_svc;

static const std::array<const char*, 5> available = {"hello", "world", "this", "is", "me"};

static void worker(fcb::CurrentValue<libb_message_t>& svc)
{
    std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<size_t> dis(0, available.size() - 1);

    while (!svc.stopped()) {
        svc.set({available[dis(gen)]});
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
}

FCB_EXPORT_SYMBOLS(g_svc, worker)

FCB_EXPORT const char* get_text(libb_message_t* msg)
{
    return msg ? msg->message.c_str() : "null";
}
