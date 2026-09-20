import 'dart:async';
import 'package:flutter/foundation.dart';

/// Bridges a [Stream] (a [Cubit]'s state stream, here) to go_router's
/// `refreshListenable`, which expects a [Listenable]. Without this, logging
/// in/out wouldn't re-run the redirect guard until some unrelated
/// navigation happened to trigger it.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
