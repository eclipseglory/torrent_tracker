import 'dart:async';
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
  /// Torrent file info hash bytebuffer
  Uint8List infoHashBuffer;

  final Set<Tracker> _trackers = {};

  TrackerGenerator trackerGenerator;

  AnnounceOptionsProvider provider;

  final Set<AnnounceErrorHandler> _announceErrorHandlers = {};

  // final Set<void Function(int total)> _announceAllOverOneTurnHandlers = {};

  final Set<AnnounceOverHandler> _announceOverHandlers = {};

  final Set<PeerEventHandler> _peerEventHandlers = {};

  final Set<void Function(Tracker tracker, dynamic reason)>
      _trackerDisposedHandlers = {};

  // final Set<String> _announceOverTrackers = {};

  /// [infoHashBuffer] is torrent info hash bytebuffer.
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
  TorrentAnnounceTracker(this.infoHashBuffer, this.provider,
      {this.trackerGenerator}) {
    trackerGenerator ??= TrackerGenerator.base();
    assert(provider != null, 'provider cant be null');
    assert(infoHashBuffer != null && infoHashBuffer.isNotEmpty,
        'infoHashBuffer cant be null or empty');
  }

  /// Start all trackers;
  /// If trackers dont be created , just generate all trackers;
  Future<List<bool>> startAll() async {
    var list = <Future<bool>>[];
    _trackers.forEach((tracker) {
      list.add(tracker.start(true));
    });
    return Stream.fromFutures(list).toList();
  }

  Future<List<bool>> restartAll() {
    var list = <Future<bool>>[];
    _trackers.forEach((tracker) {
      list.add(tracker.restart(true));
    });
    return Stream.fromFutures(list).toList();
  }

  /// Stop all trackers;
  Future<List<PeerEvent>> stopAll([bool force = false]) {
    var list = <Future<PeerEvent>>[];
    _trackers.forEach((tracker) {
      list.add(tracker.stop(force));
    });
    return Stream.fromFutures(list).toList();
  }

  /// Ask all trackers to complete;
  Future<List<PeerEvent>> completeAll() async {
    var list = <Future<PeerEvent>>[];
    _trackers.forEach((tracker) {
      list.add(tracker.complete());
    });
    return Stream.fromFutures(list).toList();
  }

  Tracker findTracker(String id) {
    return _trackers.singleWhere((element) => (id == element.id));
  }

  Future startTracker(String id) async {
    var tracker = findTracker(id);
    return tracker?.start();
  }

  Future stopTracker(String id, [bool force = false]) {
    var tracker = findTracker(id);
    return tracker?.stop(force);
  }

  Future completeTracker(String id) {
    var tracker = findTracker(id);
    return tracker?.complete();
  }

  bool removeTracker(String id) {
    var tracker = findTracker(id);
    if (tracker != null) {
      // _announceOverTrackers.remove(id);
      tracker.dispose();
      return _trackers.remove(tracker);
    }
    return false;
  }

  /// Close stream controller
  void _cleanup() {
    _trackers.clear();
    // _announceOverTrackers.clear();
    _peerEventHandlers.clear();
    _announceOverHandlers.clear();
    _announceErrorHandlers.clear();
  }

  Tracker _createTracker(Uri announce) {
    if (announce.port > 65535 || announce.port < 0) return null;
    var tracker =
        trackerGenerator.createTracker(announce, infoHashBuffer, provider);
    return tracker;
  }

  ///
  /// Add a [announce] url
  ///
  /// This class will generate a tracker via [announce] , if [start]
  /// is `true` , this tracker will `start`.
  bool addAnnounce(Uri announce, [bool start = true]) {
    var t = _createTracker(announce);
    if (t != null) {
      if (_trackers.add(t)) {
        _hookTrakcer(t);
        if (start) {
          t.start(true);
        }
        return true;
      }
    }
    return false;
  }

  void addAnnounces(List<Uri> announces, [bool start = true]) {
    if (announces != null) {
      announces.forEach((announce) {
        addAnnounce(announce, start);
      });
    }
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

  // bool onAllAnnounceOver(void Function(int totalTrackers) h) {
  //   return _announceAllOverOneTurnHandlers.add(h);
  // }

  // bool offAllAnnounceOver(void Function(int totalTrackers) h) {
  //   return _announceAllOverOneTurnHandlers.remove(h);
  // }

  void _fireAnnounceError(Tracker trakcer, dynamic error) {
    _announceErrorHandlers.forEach((f) {
      Timer.run(() => f(trakcer, error));
    });
  }

  void _fireAnnounceOver(Tracker trakcer, int time) {
    _announceOverHandlers.forEach((f) {
      Timer.run(() => f(trakcer, time));
    });

    // _announceOverTrackers.add(trakcer.id);

    // for (var i = 0; i < _trackers.length; i++) {
    //   var tracker = _trackers.elementAt(i);
    //   if (!_announceOverTrackers.contains(tracker.id)) {
    //     return;
    //   }
    // }
    // _announceOverTrackers.clear();
    // _announceAllOverOneTurnHandlers.forEach((h) {
    //   Timer.run(() => h(_trackers.length));
    // });
  }

  void _firePeerEvent(Tracker trakcer, PeerEvent event) {
    _peerEventHandlers.forEach((f) {
      Timer.run(() => f(trakcer, event));
    });
  }

  void _fireTrackerDisposed(Tracker trakcer, dynamic reason) {
    _trackers.remove(trakcer);
    _trackerDisposedHandlers.forEach((f) {
      Timer.run(() => f(trakcer, reason));
    });
  }

  void _hookTrakcer(Tracker tracker) {
    tracker.onAnnounceError((error) => _fireAnnounceError(tracker, error));
    tracker.onAnnounceOver((time) => _fireAnnounceOver(tracker, time));
    tracker.onPeerEvent((event) => _firePeerEvent(tracker, event));
    tracker.onDisposed(_fireTrackerDisposed);
    tracker.onCompleteEvent((event) => _firePeerEvent(tracker, event));
    tracker.onStopEvent((event) => _firePeerEvent(tracker, event));
  }

  Future dispose() async {
    _trackers.forEach((element) {
      element.dispose();
    });
    return _cleanup();
  }
}
