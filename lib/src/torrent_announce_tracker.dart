import 'dart:async';
import 'dart:typed_data';

import 'tracker/tracker.dart';
import 'tracker_generator.dart';

/// Torrent announce tracker.
///
/// Create announce trackers from torrent model. This class can start/stop
/// trackers , and send track response event or track exception to client.
class TorrentAnnounceTracker {
  /// Torrent file info hash bytebuffer
  Uint8List infoHashBuffer;

  Map<String, Tracker> trackers;

  List<Uri> announces;

  TrackerGenerator trackerGenerator;

  AnnounceOptionsProvider provider;

  StreamController _streamController;

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
  Stream start() {
    _streamController ??= StreamController();
    trackers = createTrackers(announces);
    trackers.forEach((id, tracker) {
      tracker.start().listen((event) {
        _streamController.add({'event': event, 'id': id});
      }, onError: (e) {
        _streamController.addError({'error': e, 'id': id});
      }, onDone: () {
        _streamController.add({'event': 'done', 'id': id});
        if (_checkTrackersStatus()) {
          _cleanup();
        }
      });
    });
    return _streamController.stream;
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
  Stream stop() {
    var list = <Future>[];
    list.add(_cleanup());
    trackers.forEach((id, tracker) {
      list.add(tracker.stop());
    });
    return Stream.fromFutures(list);
  }

  /// Ask all trackers to complete;
  Stream complete() {
    var list = <Future>[];
    list.add(_cleanup());
    trackers.forEach((id, tracker) {
      list.add(tracker.complete());
    });
    return Stream.fromFutures(list);
  }

  Stream startTracker(String id) {
    var tracker = trackers[id];
    if (tracker != null) return tracker.start();
    return Stream.empty();
  }

  Future stopTracker(String id, [bool force = false]) {
    var tracker = trackers[id];
    if (tracker != null) return tracker.stop(force);
    return Future.value(false);
  }

  Future completeTracker(String id) {
    var tracker = trackers[id];
    if (tracker != null) return tracker.complete();
    return Future.value(false);
  }

  /// Close stream controller
  Future _cleanup() {
    var f = _streamController?.close();
    _streamController = null;
    return f;
  }

  Map<String, Tracker> createTrackers(List<Uri> announces) {
    trackers ??= {};
    trackers.clear();
    announces.forEach((announce) {
      var tracker =
          trackerGenerator.createTracker(announce, infoHashBuffer, provider);
      if (tracker != null) trackers[tracker.id] = tracker;
    });
    return trackers;
  }
}
