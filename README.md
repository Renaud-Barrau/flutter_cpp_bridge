# flutter_cpp_bridge

A Flutter package that simplifies calling C++ code from Dart via `dart:ffi`.

Instead of writing raw FFI bindings by hand, `flutter_cpp_bridge` gives you
three building blocks — **Service**, **ServicePool**, and **StandaloneService**
— that handle library loading, lifecycle management, and periodic message
polling.

> **Target platform: Linux.**
> This package is designed for Linux-first deployments, including embedded
> targets such as [flutter-pi](https://github.com/ardera/flutter-pi)
> (Raspberry Pi and similar SBCs). The Dart abstractions are
> platform-agnostic, but the C++ build configuration and `.so` loading
> convention in this repo assume a Linux environment.

## Features

- Load any C++ shared library (`.so`) with a single line.
- Automatic start/stop lifecycle for your C++ services.
- Periodic polling loop that feeds C++ messages into Dart streams.
- Clean subclassing pattern to bind additional native functions.
- Standalone services that run independently, outside of a pool.
- Designed for embedded Linux / flutter-pi use cases.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_cpp_bridge:
    git:
      url: https://github.com/Renaud-Barrau/flutter_cpp_bridge
```

> The package is not yet published on pub.dev. Install it directly from GitHub
> using the `git` dependency syntax above.

## C++ side

Each library must export four functions using C linkage. These are the only
mandatory symbols; everything else is optional and can be added per-library.

```cpp
#define EXPORT extern "C" __attribute__((visibility("default")))

EXPORT void  start_service();
EXPORT void  stop_service();
EXPORT YourMessageType* get_next_message();   // nullptr when queue is empty
EXPORT void  free_message(YourMessageType*);
```

- **`start_service`** / **`stop_service`**: start and stop the service (e.g.
  spawn/join a worker thread).
- **`get_next_message`**: returns a pointer to the next pending message, or
  `nullptr` if the queue is empty. The C++ side owns the memory.
- **`free_message`**: called by Dart when it is done with a message. The
  pointer must remain valid until this function returns.

Any extra functions (to read fields, send commands, etc.) can be exported and
bound on the Dart side through subclassing.

### Minimal pooled service (C++)

A service that produces messages at a regular interval:

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
            { std::lock_guard<std::mutex> lock(mtx); queue.push_back({i++}); }
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
    for (size_t i = 0; i < queue.size(); ++i)
        if (&queue[i] == msg) { queue.erase(queue.begin() + i); break; }
}

// Extra getter bound on the Dart side
EXPORT int get_value(my_message_t* msg) { return msg->value; }
```

### Minimal standalone service (C++)

A service used as a command sink (no message queue needed). The four mandatory
symbols still have to be present, but `get_next_message` always returns
`nullptr` and `free_message` is a no-op:

```cpp
#include <cstdio>

#define EXPORT extern "C" __attribute__((visibility("default")))

EXPORT void  start_service()  {}
EXPORT void  stop_service()   {}
EXPORT void* get_next_message() { return nullptr; }
EXPORT void  free_message([[maybe_unused]] void* msg) {}

// The actual function this library exposes
EXPORT void hello() {
    printf("Hello from C++!\n");
    fflush(stdout);
}
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
final pool    = ServicePool();
final service = MyService('libmyservice.so');

service.assignJob((msg) {
  if (msg != nullptr) {
    print('value: ${service.getValue(msg)}');
    // freeMessage is called automatically after this callback returns
  }
});

pool.addService(service);          // also calls start_service
pool.startPolling(                 // default interval: 100 ms
  interval: const Duration(milliseconds: 50),
);
```

Call `pool.dispose()` to stop all services and cancel the timer.

### 3. Standalone services

For libraries that don't produce a message queue (command sinks, loggers,
one-shot callers…), extend `StandaloneService`. The C++ `start_service` is
called automatically in the constructor:

```dart
class HelloService extends StandaloneService {
  HelloService(super.libname) {
    hello = lib
        .lookup<NativeFunction<Void Function()>>('hello')
        .asFunction<void Function()>();
  }

  late final void Function() hello;
}

final greeter = HelloService('libhello.so');
greeter.hello(); // prints "Hello from C++!" — C++ service already running
// ...
greeter.dispose(); // calls stop_service
```

### 4. Sharing service instances across the app

Use static members on a dedicated class to avoid threading service instances
through constructors:

```dart
class Services {
  static final MyService   my      = MyService('libmyservice.so');
  static final HelloService greeter = HelloService('libhello.so');
}

// Anywhere in the app:
Services.greeter.hello();
```

## Compiling your C++ libraries (Linux)

### CMakeLists for your library

Create one `CMakeLists.txt` per library. The `PREFIX ""` prevents CMake from
generating `libmyservice.so` instead of `myservice.so`, which must match the
name you pass to `DynamicLibrary.open`:

```cmake
cmake_minimum_required(VERSION 3.13)
project(myservice LANGUAGES CXX)

add_library(myservice SHARED myservice.cpp)
target_compile_features(myservice PRIVATE cxx_std_17)
set_target_properties(myservice PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""               # produce myservice.so, not libmyservice.so
)
```

### Wiring into the Flutter app's CMakeLists.txt

In your Flutter app's `linux/CMakeLists.txt`, add the subdirectory and install
the resulting `.so` into the bundle's `lib/` directory:

```cmake
# Build the library
add_subdirectory("path/to/myservice")

# Install alongside the app (INSTALL_BUNDLE_LIB_DIR is set by Flutter's CMake)
install(TARGETS myservice
  LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
```

The Flutter Linux runner automatically sets `RPATH` to `$ORIGIN/lib`, so the
dynamic linker will find `.so` files in `bundle/lib/` at runtime without any
extra `LD_LIBRARY_PATH` configuration.

> **flutter-pi note:** bundle and deploy the `.so` files to the same `lib/`
> directory relative to your app executable. flutter-pi honours the same
> `$ORIGIN/lib` RPATH convention as the desktop Linux runner.

## Example

A complete working example is in the [`example/`](example/) folder. It
demonstrates:

| Library | Type | What it does |
|---------|------|--------------|
| `liba.so` | Pooled `Service` | Emits random RGB colours every 2 s |
| `libb.so` | Pooled `Service` | Emits random words every 2 s |
| `libalone.so` | `StandaloneService` | Exposes a `hello()` command, called on each colour update |

## Platform support

| Platform | Status |
|----------|--------|
| Linux (desktop & embedded) | **Primary target** |
| flutter-pi (Raspberry Pi, SBCs) | **Intended use case** |
| macOS / Windows | The Dart abstractions work as-is; `.so` loading and CMake wiring are Linux-specific and would need adapting. |
| Android / iOS | Not tested. `dart:ffi` works on these platforms but the build integration is not provided. |
