import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity and connection type.
/// Used for data-saver mode, bridge auto-reconnect, etc.
class ConnectivityController {
  ConnectivityController._();
  static final ConnectivityController inst = ConnectivityController._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  ConnectivityResult _type = ConnectivityResult.wifi;
  ConnectivityResult get type => _type;
  bool get isOnline => _type != ConnectivityResult.none;
  bool get isWifi => _type == ConnectivityResult.wifi;
  bool get isMobile => _type == ConnectivityResult.mobile;

  final List<void Function()> _onRestoredCallbacks = [];
  bool _wasOffline = false;

  void init() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final r = results.isNotEmpty ? results.first : ConnectivityResult.none;
      final wasOffline = !isOnline;
      _type = r;
      if (wasOffline && isOnline) {
        for (final cb in _onRestoredCallbacks) {
          cb();
        }
      }
      _wasOffline = !isOnline;
    });
  }

  void onConnectionRestored(void Function() cb) => _onRestoredCallbacks.add(cb);

  void dispose() => _sub?.cancel();
}
