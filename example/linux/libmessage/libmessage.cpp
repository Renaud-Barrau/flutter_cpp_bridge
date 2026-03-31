// example/linux/libmessage/libmessage.cpp
//
// Byte-buffer service example using fcb::BytesQueue + FlatBuffers.
//
// The worker alternates between two payload types every second:
//   • even id  → ColorMsg  (r, g, b computed from id)
//   • odd  id  → TextMsg   ("Message #<id>")
//
// On the Dart side, read the buffer via get_msg_bytes/get_msg_len, then
// deserialise with Message.fromBuffer() (messages_generated.dart) and
// dispatch on payloadType.

#include "flutter_cpp_bridge/service_helpers.h"
#include "messages_generated.h"   // generated from messages.fbs by CMake

#include <chrono>
#include <string>
#include <thread>

using namespace fcb_msgs;

static fcb::BytesQueue g_svc;

static void worker(fcb::BytesQueue& svc) {
    uint32_t id = 0;

    while (!svc.stopped()) {
        flatbuffers::FlatBufferBuilder fbb;

        if (id % 2 == 0) {
            // ── ColorMsg ──────────────────────────────────────────────────
            auto color = CreateColorMsg(
                fbb,
                static_cast<uint8_t>(id * 37  % 256),
                static_cast<uint8_t>(id * 71  % 256),
                static_cast<uint8_t>(id * 113 % 256));
            fbb.Finish(
                CreateMessage(fbb, id, Payload_ColorMsg, color.Union()));
        } else {
            // ── TextMsg ───────────────────────────────────────────────────
            auto text  = fbb.CreateString("Message #" + std::to_string(id));
            auto tmsg  = CreateTextMsg(fbb, text);
            fbb.Finish(
                CreateMessage(fbb, id, Payload_TextMsg, tmsg.Union()));
        }

        svc.push(fcb::BytesMsg{
            fbb.GetBufferPointer(),
            fbb.GetBufferPointer() + fbb.GetSize()
        });

        ++id;
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

// Exports the five mandatory symbols + get_msg_bytes() + get_msg_len().
FCB_EXPORT_BYTES_SYMBOLS(g_svc, worker)
