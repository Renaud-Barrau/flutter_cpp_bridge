# flutter_cpp_bridge

A Flutter package that simplifies calling C++ code from Dart via `dart:ffi`.

Instead of writing raw FFI bindings by hand, `flutter_cpp_bridge` gives you
three building blocks — **Service**, **ServicePool**, and **StandaloneService**
— that handle library loading, lifecycle management, and event-driven message
delivery.

> **Target platform: Linux.**
> This package is designed for Linux-first deployments, including embedded
> targets such as [flutter-pi](https://github.com/ardera/flutter-pi)
> (Raspberry Pi and similar SBCs). The Dart abstractions are
> platform-agnostic, but the C++ build configuration and `.so` loading
> convention in this repo assume a Linux environment.

## Features

- Load any C++ shared library (`.so`) with a single line.
- Automatic start/stop lifecycle for your C++ services.
- **Event-driven message delivery** via `NativeCallable`: the C++ worker calls
  a Dart callback when a message is ready — zero CPU consumption at idle.
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

## Your project layout

For each C++ service you want to call from Dart, you need:

- A **Dart wrapper class** in `lib/` that extends `Service` or `StandaloneService`
- A **C++ source file** + **CMakeLists.txt** in `linux/<myservice>/`
- Two small additions to your app's `linux/CMakeLists.txt`

```
my_flutter_app/
├── pubspec.yaml                    ← add flutter_cpp_bridge dependency
├── lib/
│   ├── main.dart
│   └── myservice.dart             ← extends Service, binds extra C functions
└── linux/
    ├── CMakeLists.txt             ← add_subdirectory + install(TARGETS …)
    └── myservice/
        ├── CMakeLists.txt         ← add_library, PREFIX "", include dirs
        └── myservice.cpp          ← your struct + worker + FCB_EXPORT_SYMBOLS
```

The sections below walk through each of these files.

## C++ side

Each library must export **five** functions using C linkage. These are the only
mandatory symbols; everything else is optional and can be added per-library.

```cpp
#define EXPORT extern "C" __attribute__((visibility("default")))

EXPORT void  start_service();
EXPORT void  stop_service();
EXPORT YourMessageType* get_next_message();   // nullptr when queue is empty
EXPORT void  free_message(YourMessageType*);
EXPORT void  set_message_callback(void (*cb)());
```

- **`start_service`** / **`stop_service`**: start and stop the service (e.g.
  spawn/join a worker thread).
- **`get_next_message`**: returns a pointer to the next pending message, or
  `nullptr` if the queue is empty. The C++ side owns the memory.
- **`free_message`**: called by Dart when it is done with a message. The
  pointer must remain valid until this function returns.
- **`set_message_callback`**: stores the function pointer `cb`. The C++ worker
  calls `cb()` (from any thread) immediately after pushing a new message. Dart
  then drains the whole queue on the event loop — no periodic timer needed.

Any extra functions (to read fields, send commands, etc.) can be exported and
bound on the Dart side through subclassing.

### C++ helpers (recommended)

The package ships a header-only helper at
`linux/include/flutter_cpp_bridge/service_helpers.h`.
It provides two template types and macros that generate all five mandatory
symbols, so you only write what is unique to your service.

The complete CMake wiring (defining `FCB_CPP_INCLUDE` and the `install` rule)
is covered in [Compiling your C++ libraries](#compiling-your-c-libraries-linux)
below.

**Pooled service — queue variant** (`fcb::Queue<T>`):
Each `push()` enqueues one message; Dart reads them FIFO.
Uses `std::deque` so `push_back()` never invalidates existing pointers.

```cpp
#include <chrono>
#include "flutter_cpp_bridge/service_helpers.h"

struct my_message_t { int value; };

static fcb::Queue<my_message_t> g_svc;

static void worker(fcb::Queue<my_message_t>& svc) {
    int i = 0;
    while (!svc.stopped()) {
        svc.push({i++});
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

FCB_EXPORT_SYMBOLS(g_svc, worker)

FCB_EXPORT int get_value(my_message_t* msg) { return msg->value; }
```

**Pooled service — current-value variant** (`fcb::CurrentValue<T>`):
`set()` overwrites the single stored value; Dart reads it once then releases.
Useful when only the latest value matters (e.g. a sensor reading).

```cpp
#include <chrono>
#include "flutter_cpp_bridge/service_helpers.h"

struct sensor_msg_t { float temperature; };

static fcb::CurrentValue<sensor_msg_t> g_svc;

static void worker(fcb::CurrentValue<sensor_msg_t>& svc) {
    while (!svc.stopped()) {
        svc.set({read_sensor()});
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
}

FCB_EXPORT_SYMBOLS(g_svc, worker)
```

**Standalone service** (no message queue):

```cpp
#include <cstdio>
#include "flutter_cpp_bridge/service_helpers.h"

FCB_EXPORT_STANDALONE_NOOP()

FCB_EXPORT void hello() {
    printf("Hello from C++!\n");
    fflush(stdout);
}
```

For standalone services that need real start/stop logic, use
`FCB_EXPORT_STANDALONE(start_fn, stop_fn)` instead.

### Manual implementation (without helpers)

If you prefer to write the five symbols by hand — or need behaviour not covered
by the helpers — see the full manual example below. The pattern used by the
helpers (`std::deque` + `_ready` flag) is described in the comments.

**Pooled service (manual):**

```cpp
#include <deque>
#include <mutex>
#include <thread>
#include <chrono>
#include <atomic>

#define FCB_EXPORT extern "C" __attribute__((visibility("default")))

struct my_message_t { int value; };

static std::deque<my_message_t> queue;  // deque: push_back never invalidates pointers
static std::mutex mtx;
static std::atomic<bool> running{false};
static void (*g_callback)() = nullptr;

FCB_EXPORT void set_message_callback(void (*cb)()) { g_callback = cb; }

FCB_EXPORT void start_service() {
    running = true;
    std::thread([] {
        int i = 0;
        while (running) {
            { std::lock_guard<std::mutex> lock(mtx); queue.push_back({i++}); }
            if (g_callback) g_callback();
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }).detach();
}

FCB_EXPORT void stop_service()  { running = false; }

FCB_EXPORT my_message_t* get_next_message() {
    std::lock_guard<std::mutex> lock(mtx);
    return queue.empty() ? nullptr : &queue.front();
}

FCB_EXPORT void free_message(my_message_t* msg) {
    std::lock_guard<std::mutex> lock(mtx);
    for (auto it = queue.begin(); it != queue.end(); ++it)
        if (&(*it) == msg) { queue.erase(it); break; }
}

FCB_EXPORT int get_value(my_message_t* msg) { return msg->value; }
```

**Standalone service (manual):**

```cpp
#include <cstdio>

#define FCB_EXPORT extern "C" __attribute__((visibility("default")))

FCB_EXPORT void  start_service()  {}
FCB_EXPORT void  stop_service()   {}
FCB_EXPORT void* get_next_message() { return nullptr; }
FCB_EXPORT void  free_message([[maybe_unused]] void* msg) {}
FCB_EXPORT void  set_message_callback([[maybe_unused]] void (*cb)()) {}

FCB_EXPORT void hello() {
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

### 2. Lifecycle management

Register a job **before** starting the service so no message is ever dropped,
then choose the lifecycle approach that fits your app.

#### Option A — `ServicePool` (no extra dependencies)

```dart
final pool    = ServicePool();
final service = MyService('libmyservice.so');

// Register first — before addService — so no early message is missed.
service.assignJob((msg) {
  print('value: ${service.getValue(msg)}');
  // freeMessage is called automatically after this callback returns.
});

pool.addService(service);   // calls start_service; Dart wakes up on demand
// ...
pool.dispose();             // stops all services, releases native callbacks
```

`ServicePool` is a thin convenience wrapper: it calls `startService()` for you
and lets you stop all services with a single `pool.dispose()`. It carries no
state beyond the list of registered services.

#### Option B — Riverpod `Notifier` (for apps already using flutter_riverpod)

Each service lives inside its own `Notifier`. Riverpod manages the lifecycle
automatically: `build()` starts the service, `ref.onDispose` stops it when the
provider is no longer needed. No `ServicePool` is required.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'myservice.dart';

class MyState {
  final int value;
  const MyState({required this.value});
  MyState copyWith({int? value}) => MyState(value: value ?? this.value);
}

class MyNotifier extends Notifier<MyState> {
  @override
  MyState build() {
    final service = MyService('libmyservice.so');

    // assignJob before startService — same rule as with ServicePool.
    service.assignJob((msg) {
      state = state.copyWith(value: service.getValue(msg));
    });

    service.startService();
    ref.onDispose(service.dispose);

    return const MyState(value: 0);
  }
}

final myProvider = NotifierProvider<MyNotifier, MyState>(MyNotifier.new);
```

The provider is then consumed like any other Riverpod provider:

```dart
// In a ConsumerWidget:
final myState = ref.watch(myProvider);
Text('value: ${myState.value}');
```

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
greeter.dispose(); // calls stop_service and releases the NativeCallable
```

### 4. Sharing service instances across the app

**Without a state-management library**, use static members on a dedicated class:

```dart
// app_services.dart
class Services {
  static final MyService    my      = MyService('libmyservice.so');
  static final HelloService greeter = HelloService('libhello.so');
}

// Anywhere in the app:
Services.greeter.hello();
```

**With Riverpod**, each `NotifierProvider` is already globally accessible
through `ref` — no extra singleton class needed. Instantiation, lifecycle, and
state are all handled by the provider graph.

## How event-driven delivery works

```
C++ worker thread                 Dart event loop
─────────────────                 ───────────────
push message to queue
call g_callback()   ──────────►  _onNotify() scheduled
                                  └─ drains queue with get_next_message()
                                  └─ emits each Pointer on messageStream
                                  └─ assignJob callback runs
                                  └─ free_message called automatically
```

`NativeCallable.listener` (Dart SDK ≥ 3.1) makes this safe: the C++ thread
calls the native function pointer and returns immediately; Dart processes the
notification asynchronously on its event loop without any blocking or busy-wait.

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
target_include_directories(myservice PRIVATE "${FCB_CPP_INCLUDE}")
set_target_properties(myservice PROPERTIES
  CXX_VISIBILITY_PRESET default
  PREFIX ""               # produce myservice.so, not libmyservice.so
)
```

### Wiring into the Flutter app's CMakeLists.txt

Add the following to your Flutter app's `linux/CMakeLists.txt` (after the
standard Flutter boilerplate and before `include(flutter/generated_plugins.cmake)`):

```cmake
# Path to the flutter_cpp_bridge C++ helpers header.
# Flutter creates this symlink automatically during `flutter pub get`.
set(FCB_CPP_INCLUDE
  "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_cpp_bridge/linux/include"
)

# Build the service library.
add_subdirectory("myservice")

# Install the .so alongside the app (INSTALL_BUNDLE_LIB_DIR is set by Flutter).
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
