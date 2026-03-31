
#include "flutter_cpp_bridge/service_helpers.h"
#include "messages_generated.h"   // generated from messages.fbs by CMake
#include <zmq.hpp>

#include <chrono>
#include <string>
#include <thread>

using namespace fcb_msgs;

static fcb::BytesQueue g_svc;

static void worker(fcb::BytesQueue& svc) {
    // Connexion ZMQ (ou socket UNIX, pipe, …)
    zmq::context_t ctx;
    zmq::socket_t  sub(ctx, ZMQ_SUB);
    sub.connect("ipc:///tmp/zmq_test");
    sub.set(zmq::sockopt::subscribe, "");

    while (!svc.stopped()) {
        zmq::message_t raw;
        if (!sub.recv(raw, zmq::recv_flags::dontwait)) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }

        // Accès zero-copy au buffer reçu
        auto bytes = static_cast<const uint8_t*>(raw.data());
        auto msg   = flatbuffers::GetRoot<fcb_msgs::Message>(bytes);

        // ── Switch-case côté C++ ──────────────────────────────────────────
        switch (msg->payload_type()) {
            case fcb_msgs::Payload_ColorMsg:
                // On peut transformer, enrichir, filtrer…
                svc.push(fcb::BytesMsg(bytes, bytes + raw.size()));
                break;
            case fcb_msgs::Payload_TextMsg:
                // Exemple : on forward uniquement si le texte n'est pas vide
                if (msg->payload_as_TextMsg()->text()->size() > 0)
                    svc.push(fcb::BytesMsg(bytes, bytes + raw.size()));
                break;
            default:
                break;
        }
    }
}

// Exports the five mandatory symbols + get_msg_bytes() + get_msg_len().
FCB_EXPORT_BYTES_SYMBOLS(g_svc, worker)
