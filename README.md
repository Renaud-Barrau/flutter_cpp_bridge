# flutter_cpp_bridge

A Flutter package that simplifies calling C++ code from Dart via `dart:ffi`.

Instead of writing raw FFI bindings by hand, `flutter_cpp_bridge` gives you
three building blocks — **Service**, **ServicePool**, and **StandaloneService**
— that handle library loading, lifecycle management, and periodic message
polling.

## Features

- Load any C++ shared library (`.so`, `.dll`, `.dylib`) with a single line.
- Automatic start/stop lifecycle for your C++ services.
- Periodic polling loop that feeds C++ messages into Dart streams.
- Clean subclassing pattern to bind additional native functions.
- Standalone services that run without a pool.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_cpp_bridge: ^0.0.1
```

## C++ side

Your shared library must export four functions using C linkage:

```cpp
#define EXPORT extern "C" __attribute__((visibility("default")))

EXPORT void start_service();
EXPORT void stop_service();
EXPORT YourMessageType* get_next_message();
EXPORT void free_message(YourMessageType*);
```

- **`start_service`** / **`stop_service`**: start and stop the service (e.g.
  spawn/join a worker thread).
- **`get_next_message`**: returns a pointer to the next pending message, or
  `nullptr` if the queue is empty. The service owns the memory.
- **`free_message`**: called by the Dart side when it is done with a message.
  The service must keep the pointer valid until this function is called.

Any additional functions (to read fields from the message struct, to send
commands, etc.) can be exported and bound on the Dart side via subclassing.

### Minimal example (C++)

```cpp
#include <vector>
#include <mutex>
#include <thread>
#include <chrono>
#include <atomic>

#define EXPORT extern "C" __attribute__((visibility("default")))

struct my_message_t { int value; };

static std::vector<my_message_t> queue;
static std::mutex mtx;
static std::atomic<bool> running{false};

EXPORT void start_service() {
    running = true;
    std::thread([] {
        int i = 0;
        while (running) {
            std::lock_guard<std::mutex> lock(mtx);
            queue.push_back({i++});
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }).detach();
}

EXPORT void stop_service()  { running = false; }

EXPORT my_message_t* get_next_message() {
    std::lock_guard<std::mutex> lock(mtx);
    return queue.empty() ? nullptr : &queue.front();
}

EXPORT void free_message(my_message_t* msg) {
    std::lock_guard<std::mutex> lock(mtx);
    for (size_t i = 0; i < queue.size(); ++i) {
        if (&queue[i] == msg) { queue.erase(queue.begin() + i); break; }
    }
}

// Extra function exposed to Dart
EXPORT int get_value(my_message_t* msg) { return msg->value; }
```

## Dart / Flutter side

### 1. Subclass `Service` to bind your library

```dart
import 'dart:ffi';
import 'package:flutter_cpp_bridge/flutter_cpp_bridge.dart';

class MyService extends Service {
  MyService(super.libname) {
    getValue = lib
        .lookup<NativeFunction<Int32 Function(Pointer<BackendMsg>)>>('get_value')
        .asFunction<int Function(Pointer<BackendMsg>)>();
  }

  late final int Function(Pointer<BackendMsg>) getValue;
}
```

### 2. Create a `ServicePool` and register your service

```dart
final pool = ServicePool();
final service = MyService('libmyservice.so');

service.assignJob((msg) {
  if (msg != nullptr) {
    print('value: ${service.getValue(msg)}');
    // freeMessage is called automatically after this callback returns
  }
});

pool.addService(service);             // also calls start_service
pool.startPolling(                    // default interval: 100 ms
  interval: const Duration(milliseconds: 50),
);
```

Call `pool.dispose()` to stop all services.

### 3. Standalone services

For services that don't need a pool (e.g. command sinks, loggers):

```dart
class LoggerService extends StandaloneService {
  LoggerService(super.libname) {
    log = lib
        .lookup<NativeFunction<Void Function()>>('log_something')
        .asFunction<void Function()>();
  }
  late final void Function() log;
}

final logger = LoggerService('liblogger.so');
logger.log(); // C++ service already running
// ...
logger.dispose(); // calls stop_service
```

### 4. Sharing service instances across the app

Use static members on a dedicated class to avoid threading service instances
through constructors:

```dart
class Services {
  static final MyService my = MyService('libmyservice.so');
  static final LoggerService logger = LoggerService('liblogger.so');
}

// Anywhere in the app:
Services.logger.log();
```

## Compiling your C++ libraries (Linux)

Place your library sources inside `linux/` of your Flutter app, then update
`linux/CMakeLists.txt`:

```cmake
# Make the runtime linker look in the same directory as the binary
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Build your library (adjust path as needed)
add_subdirectory("libs")

# At the end of CMakeLists.txt — install the .so alongside the app
install(
  FILES "${PROJECT_BINARY_DIR}/libs/libmyservice.so"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
```

## Example

A complete working example is available in the [`example/`](example/) folder.
It demonstrates two pooled services (`liba` — random RGB colours, `libb` —
random text words) and one standalone service, all backed by real C++ threads.

## Platform support

| Platform | Status |
|----------|--------|
| Linux    | Supported |
| Others   | The Dart-side abstractions are platform-agnostic; only the C++ build configuration is Linux-specific in this repo. |
