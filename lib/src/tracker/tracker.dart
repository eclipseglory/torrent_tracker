import 'dart:async';
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:dtorrent_tracker/src/tracker/tracker_base.dart';

import 'peer_event.dart';

const EVENT_STARTED = 'started';
const EVENT_UPDATE = 'update';
const EVENT_COMPLETED = 'completed';
const EVENT_STOPPED = 'stopped';

///
/// An abstract class for accessing Announce to obtain data.
///
/// ```
abstract class Tracker {
  /// Tracker ID , usually use server host url to be its id.
  final String id;

  /// Torrent file info hash bytebuffer
  final Uint8List infoHashBuffer;

  /// Torrent file info hash string
  String? _infoHash;

  /// server url;
  final Uri announceUrl;

  /// The interval for looping through the announce url, in seconds,
  /// the default value is 30 minutes
  final int DEFAULT_INTERVAL_TIME = 30 * 60; // 30 minites

  /// The interval for looping scrape data, in seconds, defaults to 1 minute
  int announceScrape = 1 * 60;

  final Set<void Function(Tracker source, PeerEvent event)> _peerEventHandlers =
      {};

  final Set<void Function(Tracker source, PeerEvent? event)>
      _stopEventHandlers = {};

  final Set<void Function(Tracker source, PeerEvent? event)>
      _completeEventHandlers = {};

  final Set<void Function(Tracker source, dynamic reason)>
      _disposeEventHandlers = {};

  final Set<void Function(Tracker source, dynamic error)>
      _announceErrorHandlers = {};

  final Set<void Function(Tracker source, int intervalTime)>
      _announceOverHandlers = {};

  final Set<void Function(Tracker source)> _announceStartHandlers = {};

  Timer? _announceTimer;

  bool _disposed = false;

  bool _running = false;

  AnnounceOptionsProvider? provider;

  ///
  /// [maxRetryTime] is the max retry times if connect timeout,default is 3
  Tracker(this.id, this.announceUrl, this.infoHashBuffer, {this.provider});

  /// Torrent file info hash string
  String get infoHash {
    _infoHash ??= infoHashBuffer.fold('', (previousValue, byte) {
      var s = byte.toRadixString(16);
      if (s.length != 2) s = '0$s';
      return previousValue! + s;
    });
    return _infoHash!;
  }

  bool get isDisposed => _disposed;

  bool get isRunning => _running;

  ///
  /// Start a loop to initiate an announce visit.
  ///
  Future<bool> start() async {
    if (isDisposed) throw Exception('This tracker was disposed');
    if (isRunning) return true;
    _running = true;
    return _intervalAnnounce(EVENT_STARTED);
  }

  ///
  /// Restart the loop to initiate the announce visit.
  ///
  Future<bool> restart() async {
    if (isDisposed) throw Exception('This tracker was disposed');
    stopIntervalAnnounce();
    _running = false;
    return start();
  }

  ///
  /// The method loops through Announce until it is disposed.
  /// The interval between each iteration is announceInterval, and the subclass
  /// needs to add the interval value to the return value when implementing
  /// the announce method.
  /// The return value is compared to the existing value, and if it is different
  /// ,the current Timer is stopped and a new loop-interval timer is regenerated
  /// If announce throws an exception, the loop does not stop
  /// unless [errorOrCancel] sets the bit 'true'
  ///
  Future<bool> _intervalAnnounce(String event) async {
    if (isDisposed) {
      _running = false;
      return false;
    }
    _fireAnnounceStartEvent();
    PeerEvent? result;
    try {
      result = await announce(event, await _announceOptions);
      if (result != null) {
        result.eventType = event;
        _firePeerEvent(result);
      }
    } catch (e) {
      _fireAnnounceError(e);
      return false;
    }
    int? interval;
    if (result != null) {
      var inter = result.interval;
      var minInter = result.minInterval;
      if (inter == null) {
        interval = minInter;
      } else {
        if (minInter != null) {
          interval = math.min(inter, minInter);
        } else {
          interval = inter;
        }
      }
    }

    interval ??= DEFAULT_INTERVAL_TIME;
    _announceTimer?.cancel();
    _announceTimer =
        Timer(Duration(seconds: interval), () => _intervalAnnounce(event));
    _fireAnnounceOver(interval);
    return true;
  }

  Future dispose([dynamic reason]) async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _announceTimer?.cancel();
    _fireDisposed(reason);
    _peerEventHandlers.clear();
    _announceErrorHandlers.clear();
    _announceOverHandlers.clear();
    _stopEventHandlers.clear();
    _completeEventHandlers.clear();
    _announceStartHandlers.clear();
    _disposeEventHandlers.clear();
    await close();
  }

  Future<Map<String, dynamic>> get _announceOptions async {
    var options = <String, dynamic>{
      'downloaded': 0,
      'uploaded': 0,
      'left': 0,
      'compact': 1,
      'numwant': 50
    };
    if (provider != null) {
      var opt = await provider!.getOptions(announceUrl, infoHash);
      if (opt.isNotEmpty) options = opt;
    }
    return options;
  }

  Future close();

  void stopIntervalAnnounce() {
    _announceTimer?.cancel();
    _announceTimer = null;
  }

  /// When abruptly stopped, this method needs to be called to notify 'announce'
  /// The method calls 'announce' once with the parameter bit 'stopped'.
  /// [force] is to force off the identity, with a default value of 'false'.
  /// If 'true', the method will not call the 'announce' method
  /// Send a 'stopped' request and return a 'null' directly.
  ///
  Future<PeerEvent?> stop([bool force = false]) async {
    if (isDisposed) return null;
    stopIntervalAnnounce();
    if (force) {
      _fireStopEvent(null);
      await close();
      return null;
    }
    try {
      var re = await announce(EVENT_STOPPED, await _announceOptions);
      re?.eventType = EVENT_STOPPED;
      _fireStopEvent(re);
      await close();
      return re;
    } catch (e) {
      return null;
    }
  }

  ///
  /// When the download is complete, you need to call this method to notify
  /// announce.
  /// This method calls announce once, and the parameter bit is completed.
  ///
  Future<PeerEvent?> complete() async {
    if (isDisposed) return null;
    stopIntervalAnnounce();
    try {
      var re = await announce(EVENT_COMPLETED, await _announceOptions);
      re?.eventType = EVENT_COMPLETED;
      _fireCompleteEvent(re);
      await close();
      return re;
    } catch (e) {
      await dispose(e);
      return null;
    }
  }

  ///
  /// Visit the announce URL for data.
  /// Call the method to initiate a visit to the Announce URL,
  /// it returns a Future. If successful, it will return the data as expected.
  /// However, if any failures occur during the process, such as decoding errors
  /// or timeouts, exceptions will be thrown.
  /// The parameter eventType must be one of started, stopped, completed, and
  /// can be null.
  /// The returned data should be a [PeerEvent] object.
  /// If the 'interval' property of this object is not empty and is different
  /// from the current loop interval time, the Tracker will stop
  /// the current Timer and create a new Timer with the interval time set to
  /// the value from the returned object's 'interval'.
  ///
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options);

  bool onAnnounceError(void Function(Tracker source, dynamic error) handler) {
    return _announceErrorHandlers.add(handler);
  }

  bool offAnnounceError(void Function(Tracker source, dynamic error) handler) {
    return _announceErrorHandlers.remove(handler);
  }

  bool onPeerEvent(void Function(Tracker source, PeerEvent event) handler) {
    return _peerEventHandlers.add(handler);
  }

  bool offPeerEvent(void Function(Tracker source, PeerEvent) handler) {
    return _peerEventHandlers.remove(handler);
  }

  bool onStopEvent(void Function(Tracker source, PeerEvent?) handler) {
    return _stopEventHandlers.add(handler);
  }

  bool offStopEvent(void Function(Tracker source, PeerEvent) handler) {
    return _stopEventHandlers.remove(handler);
  }

  bool onCompleteEvent(void Function(Tracker source, PeerEvent?) handler) {
    return _completeEventHandlers.add(handler);
  }

  bool offCompleteEvent(void Function(Tracker source, PeerEvent) handler) {
    return _completeEventHandlers.remove(handler);
  }

  bool onAnnounceStart(void Function(Tracker source) handler) {
    return _announceStartHandlers.add(handler);
  }

  bool offAnnounceStart(void Function(Tracker source) handler) {
    return _announceStartHandlers.remove(handler);
  }

  bool onAnnounceOver(void Function(Tracker source, int intervalTime) handler) {
    return _announceOverHandlers.add(handler);
  }

  bool offAnnounceOver(
      void Function(Tracker source, int intervalTime) handler) {
    return _announceOverHandlers.remove(handler);
  }

  bool onDisposed(void Function(Tracker tracker, dynamic reason) handler) {
    return _disposeEventHandlers.add(handler);
  }

  bool offDisposed(void Function(Tracker, dynamic) handler) {
    return _disposeEventHandlers.remove(handler);
  }

  void _fireAnnounceStartEvent() {
    for (var handler in _announceStartHandlers) {
      Timer.run(() => handler(this));
    }
  }

  void _firePeerEvent(PeerEvent event) {
    for (var handler in _peerEventHandlers) {
      Timer.run(() => handler(this, event));
    }
  }

  void _fireStopEvent(PeerEvent? event) {
    for (var handler in _stopEventHandlers) {
      Timer.run(() => handler(this, event));
    }
  }

  void _fireCompleteEvent(PeerEvent? event) {
    for (var handler in _completeEventHandlers) {
      Timer.run(() => handler(this, event));
    }
  }

  void _fireAnnounceError(dynamic error) {
    for (var handler in _announceErrorHandlers) {
      Timer.run(() => handler(this, error));
    }
  }

  void _fireAnnounceOver(int intervalTime) {
    for (var handler in _announceOverHandlers) {
      Timer.run(() => handler(this, intervalTime));
    }
  }

  void _fireDisposed([dynamic reason]) {
    for (var handler in _disposeEventHandlers) {
      Timer.run(() => handler(this, reason));
    }
  }

  @override
  bool operator ==(other) {
    if (other is Tracker) return other.id == id;
    return false;
  }

  @override
  int get hashCode => id.hashCode;
}

abstract class AnnounceOptionsProvider {
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash);
}
