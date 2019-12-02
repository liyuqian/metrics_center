// TODO(???): Dart implementation of https://github.com/marcacohen/gcslock.
// Before that, I'll just manually make sure the FlutterCenter has only a single
// instance around the globe.
class GcsLock {
  Future<void> protectedRun(Future<void> f()) async {
    await _lock();
    try {
      await f();
    } catch (e, stacktrace) {
      print(stacktrace);
      rethrow;
    } finally {
      await _unlock();
    }
  }

  Future<void> _lock() async {}
  Future<void> _unlock() async {}

  // Ensure that _lock can be called many times from the same thread.
  // int _lockCount = 0;
}
