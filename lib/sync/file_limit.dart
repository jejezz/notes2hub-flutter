import 'dart:ffi';
import 'dart:io';

/// 열 수 있는 파일 수(RLIMIT_NOFILE)를 올린다.
///
/// macOS GUI 앱의 기본값은 256이라, 객체가 많은 저장소를 fetch/checkout하면 libgit2가
/// "Too many open files"로 실패한다. 실패해도 앱은 계속 동작해야 하므로 오류는 무시한다.
void raiseOpenFileLimit() {
  if (!(Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS)) {
    return;
  }
  try {
    final lib = DynamicLibrary.process();
    final calloc = lib
        .lookupFunction<
          Pointer<Void> Function(IntPtr, IntPtr),
          Pointer<Void> Function(int, int)
        >('calloc');
    final free = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final getrlimit = lib
        .lookupFunction<
          Int32 Function(Int32, Pointer<Uint64>),
          int Function(int, Pointer<Uint64>)
        >('getrlimit');
    final setrlimit = lib
        .lookupFunction<
          Int32 Function(Int32, Pointer<Uint64>),
          int Function(int, Pointer<Uint64>)
        >('setrlimit');
    // RLIMIT_NOFILE: macOS/iOS 8, Linux/Android 7.
    final resource = (Platform.isMacOS || Platform.isIOS) ? 8 : 7;
    final p = calloc(2, 8).cast<Uint64>();
    try {
      if (getrlimit(resource, p) != 0) return;
      const wanted = 10240; // macOS의 kern.maxfilesperproc 기본 상한
      final hard = p[1];
      final target = hard < wanted ? hard : wanted;
      if (p[0] >= target) return;
      p[0] = target;
      setrlimit(resource, p);
    } finally {
      free(p.cast());
    }
  } catch (_) {}
}
