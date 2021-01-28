import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:torrent_tracker/src/tracker/peer_event.dart';

import 'tracker/tracker.dart';
import 'tracker_generator.dart';

typedef AnnounceErrorHandler = void Function(Tracker t, dynamic error);

typedef AnnounceOverHandler = void Function(Tracker t, int time);

typedef PeerEventHandler = void Function(Tracker t, PeerEvent event);

/// Torrent announce tracker.
///
/// Create announce trackers from torrent model. This class can start/stop
/// trackers , and send track response event or track exception to client.
///
///
class TorrentAnnounceTracker {
  final Map<Uri, Tracker> _trackers = {};

  TrackerGenerator trackerGenerator;

  AnnounceOptionsProvider provider;

  final Set<AnnounceErrorHandler> _announceErrorHandlers = {};

  final Set<AnnounceOverHandler> _announceOverHandlers = {};

  final Set<PeerEventHandler> _peerEventHandlers = {};

  final Set<void Function(Tracker tracker, dynamic reason)>
      _trackerDisposedHandlers = {};

  final Set<void Function(Tracker tracker)> _announceStartHandlers = {};

  final Map<Tracker, List<dynamic>> _announceRetryTimers = {};

  final int maxRetryTime;

  final int _retryAfter = 5;

  // final Set<String> _announceOverTrackers = {};

  ///
  /// [provider] is announce options value provider , it should return a `Future<Map>` and the `Map`
  /// should contains `downloaded`,`uploaded`,`numwant`,`compact`,`left` ,`peerId`,`port` property values, these datas
  /// will be used when tracker to access remote , this class will get `AnnounceOptionProvider`'s `options`
  /// when it ready to acceess remove. I suggest that client implement `AnnounceOptionProvider` to get the options
  /// data lazyly :
  /// ```dart
  /// class MyAnnounceOptionsProvider implements AnnounceOptionProvider{
  ///     ....
  ///     Torrent torrent;
  ///     /// the file has been downloaded....
  ///     File downloadedFile;
  ///
  ///     Future getOptions(Uri uri,String infoHash) async{
  ///         // 可以根据uri以及infoHash来确定需要返回的参数。也就是说，实际上这个provider可以在多个
  ///         // TorrentTracker一起使用。
  ///         var someport;
  ///         if(infoHash..... ){
  ///             someport = ... // port depends infohash or uri...
  ///         }
  ///         /// maybe need to await some IO operations...
  ///         return {
  ///           'port' : someport,
  ///           'downloaded' : downloadedFile.length,
  ///           'left' : torrent.length - file.length,
  ///           ....
  ///         };
  ///     }
  /// }
  /// ```
  ///
  /// [trackerGenerator] is a class which implements `TrackerGenerator`.
  /// Actually client dosn't need to care about it if client dont want to extends some other schema tracker,
  /// `BaseTrackerGenerator` has implemented for creating `https` `http` `udp` schema tracker, this parameter's default value
  /// is a `BaseTrackerGenerator` instance.
  ///
  /// However, if client has implemented other schema trackers , such as `ws`(web socket), it can create a new tracker generator
  /// base on `BaseTrackerGenerator`:
  ///
  /// ```dart
  /// class MyTrackerGenerator extends BaseTrackerGenerator{
  ///   .....
  ///   @override
  ///   Tracker createTracker(
  ///    Uri announce, Uint8List infoHashBuffer, AnnounceOptionsProvider provider) {
  ///     if (announce.isScheme('ws')) {
  ///        return MyWebSocketTracker(announce, infoHashBuffer, provider: provider);
  ///     }
  ///     return super.createTracker(announce,infoHashBuffer,provider);
  ///   }
  /// }
  /// ```
  TorrentAnnounceTracker(this.provider,
      {this.trackerGenerator, this.maxRetryTime = 3}) {
    trackerGenerator ??= TrackerGenerator.base();
    assert(provider != null, 'provider cant be null');
  }

  int get trackersNum => _trackers.length;

  Future<List<bool>> restartAll() {
    var list = <Future<bool>>[];
    _trackers.forEach((url, tracker) {
      list.add(tracker.restart());
    });
    return Stream.fromFutures(list).toList();
  }

  void removeTracker(Uri url) {
    var tracker = _trackers.remove(url);
    tracker?.dispose();
  }

  /// Close stream controller
  void _cleanup() {
    _trackers.clear();
    _peerEventHandlers.clear();
    _announceOverHandlers.clear();
    _announceErrorHandlers.clear();
    _announceStartHandlers.clear();
    _announceRetryTimers.forEach((key, record) {
      if (record != null) {
        record[0].cancel();
      }
    });
    _announceRetryTimers.clear();
  }

  Tracker _createTracker(Uri announce, Uint8List infohash) {
    if (announce == null) return null;
    if (infohash == null || infohash.length != 20) return null;
    if (announce.port > 65535 || announce.port < 0) return null;
    var tracker = trackerGenerator.createTracker(announce, infohash, provider);
    return tracker;
  }

  ///
  /// Create and run a tracker via [announce] url
  ///
  /// This class will generate a tracker via [announce] , duplicate [announce]
  /// will be ignore.
  void runTracker(Uri url, Uint8List infoHash,
      {String event = EVENT_STARTED, bool force = false}) {
    if (isDisposed) return;
    var tracker = _trackers[url];
    if (tracker == null) {
      tracker = _createTracker(url, infoHash);
      if (tracker == null) return;
      _hookTrakcer(tracker);
      _trackers[url] = tracker;
    }
    if (tracker.isDisposed) return;
    if (event == EVENT_STARTED) {
      tracker.start();
    }
    if (event == EVENT_STOPPED) {
      tracker.stop(force);
    }
    if (event == EVENT_COMPLETED) {
      tracker.complete();
    }
  }

  /// Create and run a tracker via the its url.
  ///
  /// [infoHash] is the bytes of the torrent infohash.
  void runTrackers(Iterable<Uri> announces, Uint8List infoHash,
      {String event = EVENT_STARTED,
      bool forceStop = false,
      int maxRetryTimes = 3}) {
    if (isDisposed) return;
    if (announces != null) {
      announces.forEach((announce) {
        runTracker(announce, infoHash, event: event, force: forceStop);
      });
    }
  }

  /// Restart all trackers(which is record with this class instance , some of the trackers
  /// was removed because it can not access)
  bool restartTracker(Uri url) {
    var tracker = _trackers[url];
    tracker?.restart();
    return tracker != null;
  }

  bool onAnnounceError(void Function(Tracker source, dynamic error) f) {
    return _announceErrorHandlers.add(f);
  }

  bool offAnnounceError(void Function(Tracker source, dynamic error) f) {
    return _announceErrorHandlers.remove(f);
  }

  bool onAnnounceOver(void Function(Tracker source, int time) f) {
    return _announceOverHandlers.add(f);
  }

  bool offAnnounceOver(void Function(Tracker source, int time) f) {
    return _announceOverHandlers.remove(f);
  }

  bool onPeerEvent(void Function(Tracker source, PeerEvent event) f) {
    return _peerEventHandlers.add(f);
  }

  bool offPeerEvent(void Function(Tracker source, PeerEvent event) f) {
    return _peerEventHandlers.remove(f);
  }

  bool onTrackerDispose(void Function(Tracker source, dynamic reason) f) {
    return _trackerDisposedHandlers.add(f);
  }

  bool offTrackerDispose(void Function(Tracker source, dynamic reason) f) {
    return _trackerDisposedHandlers.remove(f);
  }

  bool onAnnounceStart(void Function(Tracker source) f) {
    return _announceStartHandlers.add(f);
  }

  bool offAnnounceStart(void Function(Tracker source) f) {
    return _announceStartHandlers.remove(f);
  }

  void _fireAnnounceError(Tracker tracker, dynamic error) {
    if (isDisposed) return;
    var record = _announceRetryTimers.remove(tracker);
    if (tracker.isDisposed) return;
    var times = 0;
    if (record != null) {
      record[0].cancel();
      times = record[1];
    }
    if (times >= maxRetryTime) {
      tracker.dispose('NO MORE RETRY ($times/$maxRetryTime)');
      return;
    }
    var re_time = _retryAfter * pow(2, times);
    var timer = Timer(Duration(seconds: re_time), () {
      if (tracker.isDisposed || isDisposed) return;
      _unHookTracker(tracker);
      var url = tracker.announceUrl;
      var infoHash = tracker.infoHashBuffer;
      _trackers.remove(url);
      tracker.dispose();
      runTracker(url, infoHash);
    });
    times++;
    _announceRetryTimers[tracker] = [timer, times];
    _announceErrorHandlers.forEach((f) {
      Timer.run(() => f(tracker, error));
    });
  }

  void _fireAnnounceOver(Tracker tracker, int time) {
    var record = _announceRetryTimers.remove(tracker);
    if (record != null) {
      record[0].cancel();
    }
    _announceOverHandlers.forEach((f) {
      Timer.run(() => f(tracker, time));
    });
  }

  void _firePeerEvent(Tracker tracker, PeerEvent event) {
    var record = _announceRetryTimers.remove(tracker);
    if (record != null) {
      record[0].cancel();
    }
    _peerEventHandlers.forEach((f) {
      Timer.run(() => f(tracker, event));
    });
  }

  void _fireTrackerDisposed(Tracker tracker, dynamic reason) {
    var record = _announceRetryTimers.remove(tracker);
    if (record != null) {
      record[0].cancel();
    }
    _trackers.remove(tracker.announceUrl);
    _trackerDisposedHandlers.forEach((f) {
      Timer.run(() => f(tracker, reason));
    });
  }

  void _fireAnnounceStart(Tracker tracker) {
    _announceStartHandlers.forEach((f) {
      Timer.run(() => f(tracker));
    });
  }

  void _hookTrakcer(Tracker tracker) {
    tracker.onAnnounceStart(_fireAnnounceStart);
    tracker.onAnnounceError(_fireAnnounceError);
    tracker.onAnnounceOver(_fireAnnounceOver);
    tracker.onPeerEvent(_firePeerEvent);
    tracker.onDisposed(_fireTrackerDisposed);
    tracker.onCompleteEvent(_firePeerEvent);
    tracker.onStopEvent(_firePeerEvent);
  }

  void _unHookTracker(Tracker tracker) {
    tracker.offAnnounceStart(_fireAnnounceStart);
    tracker.offAnnounceError(_fireAnnounceError);
    tracker.offAnnounceOver(_fireAnnounceOver);
    tracker.offPeerEvent(_firePeerEvent);
    tracker.offDisposed(_fireTrackerDisposed);
    tracker.offCompleteEvent(_firePeerEvent);
    tracker.offStopEvent(_firePeerEvent);
  }

  Future<List> stop([bool force = false]) {
    if (isDisposed) return null;
    var l = <Future>[];
    _trackers.forEach((url, element) {
      l.add(element.stop(force));
    });
    return Stream.fromFutures(l).toList();
  }

  Future<List> complete() {
    if (isDisposed) return null;
    var l = <Future>[];
    _trackers.forEach((url, element) {
      l.add(element.complete());
    });
    return Stream.fromFutures(l).toList();
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future dispose() async {
    if (isDisposed) return;
    _disposed = true;
    var f = <Future>[];
    _trackers.forEach((url, element) {
      _unHookTracker(element);
      f.add(element.dispose());
    });
    _cleanup();
    return Stream.fromFutures(f).toList();
  }
}
