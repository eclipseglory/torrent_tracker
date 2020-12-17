import 'dart:async';
import 'dart:developer';
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

  Map<String, Tracker> trackers;

  List<Uri> announces;

  TrackerGenerator trackerGenerator;

  AnnounceOptionsProvider provider;

  final Set<AnnounceErrorHandler> _announceErrorHandlers = {};

  final Set<void Function(int total)> _announceAllOverOneTurnHandlers = {};

  final Set<AnnounceOverHandler> _announceOverHandlers = {};

  final Set<PeerEventHandler> _peerEventHandlers = {};

  final Set<String> _announceOverTrackers = {};

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
  TorrentAnnounceTracker(this.announces, this.infoHashBuffer, this.provider,
      {this.trackerGenerator}) {
    trackerGenerator ??= TrackerGenerator.base();
    assert(announces != null, 'announces cant be null');
    assert(provider != null, 'provider cant be null');
    assert(infoHashBuffer != null && infoHashBuffer.isNotEmpty,
        'infoHashBuffer cant be null or empty');
  }

  /// Start all trackers;
  /// If trackers dont be created , just generate all trackers;
  void start([bool errorOrRemove = false]) async {
    trackers = createTrackers(announces);
    log('开始运行announce....');
    trackers.forEach((id, tracker) {
      tracker.start(errorOrRemove);
    });
  }

  /// Check if all trackers has been stopped
  bool _checkTrackersStatus() {
    for (var id in trackers.keys) {
      var tracker = trackers[id];
      if (!tracker.isStopped) {
        return false;
      }
    }
    return true;
  }

  /// Stop all trackers;
  Future<List<PeerEvent>> stop([bool force = false]) {
    var list = <Future<PeerEvent>>[];
    _cleanup();
    trackers.forEach((id, tracker) {
      list.add(tracker.stop(force));
    });
    return Stream.fromFutures(list).toList();
  }

  /// Ask all trackers to complete;
  Future<List<PeerEvent>> complete() {
    var list = <Future<PeerEvent>>[];
    _cleanup();
    trackers.forEach((id, tracker) {
      list.add(tracker.complete());
    });
    return Stream.fromFutures(list).toList();
  }

  Future startTracker(String id) async {
    var tracker = trackers[id];
    if (tracker != null) return tracker.start();
  }

  Future stopTracker(String id, [bool force = false]) {
    var tracker = trackers[id];
    if (tracker != null) return tracker.stop(force);
    return null;
  }

  Future completeTracker(String id) {
    var tracker = trackers[id];
    if (tracker != null) return tracker.complete();
    return null;
  }

  Tracker removeTracker(String id) {
    _announceOverTrackers.remove(id);
    return trackers.remove(id);
  }

  /// Close stream controller
  void _cleanup() {
    trackers.clear();
    _announceOverTrackers.clear();
    _peerEventHandlers.clear();
    _announceOverHandlers.clear();
    _announceErrorHandlers.clear();
  }

  Map<String, Tracker> createTrackers(List<Uri> announces) {
    trackers ??= {};
    trackers.clear();
    announces.forEach((announce) {
      if (announce.port > 65535) return;
      var tracker =
          trackerGenerator.createTracker(announce, infoHashBuffer, provider);
      if (tracker != null && trackers[tracker.id] == null) {
        trackers[tracker.id] = tracker;
        _hookTrakcer(tracker);
      }
    });
    return trackers;
  }

  void onAnnounceError(void Function(Tracker source, dynamic error) f) {
    _announceErrorHandlers.add(f);
  }

  void onAnnounceOver(void Function(Tracker source, int time) f) {
    _announceOverHandlers.add(f);
  }

  void onPeerEvent(void Function(Tracker source, PeerEvent event) f) {
    _peerEventHandlers.add(f);
  }

  void onAllAnnounceOver(void Function(int totalTrackers) h) {
    _announceAllOverOneTurnHandlers.add(h);
  }

  void _fireAnnounceError(Tracker trakcer, dynamic error) {
    _announceErrorHandlers.forEach((f) {
      Timer.run(() => f(trakcer, error));
    });
  }

  void _fireAnnounceOver(Tracker trakcer, int time) {
    _announceOverHandlers.forEach((f) {
      Timer.run(() => f(trakcer, time));
    });

    _announceOverTrackers.add(trakcer.id);

    for (var i = 0; i < trackers.keys.length; i++) {
      var id = trackers.keys.elementAt(i);
      if (!_announceOverTrackers.contains(id)) {
        return;
      }
    }
    _announceOverTrackers.clear();
    _announceAllOverOneTurnHandlers.forEach((h) {
      Timer.run(() => h(trackers.length));
    });
    // Timer.run(() => )
  }

  void _firePeerEvent(Tracker trakcer, PeerEvent event) {
    _peerEventHandlers.forEach((f) {
      Timer.run(() => f(trakcer, event));
    });
  }

  void addPeer(Uri host, Uri peer, String infoHash) {
    var event = PeerEvent(infoHash, peer);
    event.addPeer(peer);
    _firePeerEvent(null, event);
  }

  void _hookTrakcer(Tracker tracker) {
    tracker.onAnnounceError((error) => _fireAnnounceError(tracker, error));
    tracker.onAnnounceOver((time) => _fireAnnounceOver(tracker, time));
    tracker.onPeerEvent((event) => _firePeerEvent(tracker, event));
  }

  Future dispose() async {
    trackers.values.forEach((element) {
      element.dispose();
    });
    return _cleanup();
  }
}
