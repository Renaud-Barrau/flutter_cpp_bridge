/// A Flutter package that simplifies calling C++ code via FFI.
///
/// The three main building blocks are:
/// - [Service]: base class to wrap a C++ shared library
/// - [ServicePool]: manages multiple services with periodic polling
/// - [StandaloneService]: a self-starting service that runs independently
library;

export 'service.dart';
export 'service_pool.dart';
export 'standalone_service.dart';
