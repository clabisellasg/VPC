import 'dart:async';
import 'dart:js_interop';

@JS('navigator.onLine')
external bool get _isOnline;

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction listener);

@JS('window.removeEventListener')
external void _removeEventListener(String type, JSFunction listener);

Stream<bool> watchBrowserOnlineStatus() {
  late final StreamController<bool> controller;
  late final JSFunction listener;

  void report(JSAny? _) => controller.add(_isOnline);

  listener = report.toJS;
  controller = StreamController<bool>(
    onListen: () {
      controller.add(_isOnline);
      _addEventListener('online', listener);
      _addEventListener('offline', listener);
    },
    onCancel: () {
      _removeEventListener('online', listener);
      _removeEventListener('offline', listener);
    },
  );
  return controller.stream.distinct();
}
