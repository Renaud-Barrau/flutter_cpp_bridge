#include <chrono>
#include <cstdint>
#include <random>
#include "flutter_cpp_bridge/service_helpers.h"

struct liba_message_t
{
    uint8_t r, g, b;
};

static fcb::Queue<liba_message_t> g_svc;

static void worker(fcb::Queue<liba_message_t>& svc)
{
    std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<uint8_t> dis(0, 255);

    while (!svc.stopped()) {
        svc.push({dis(gen), dis(gen), dis(gen)});
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
}

FCB_EXPORT_SYMBOLS(g_svc, worker)

FCB_EXPORT uint32_t get_hexa_color(liba_message_t* msg)
{
    return 0xFF000000u | (uint32_t(msg->r) << 16) | (uint32_t(msg->g) << 8) | msg->b;
}
