import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browser_online_status_stub.dart'
    if (dart.library.js_interop) 'browser_online_status_web.dart';

final browserOnlineProvider = StreamProvider<bool>(
  (ref) => watchBrowserOnlineStatus(),
);
