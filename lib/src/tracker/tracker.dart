import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'dart:typed_data';

import 'peer_event.dart';

const EVENT_STARTED = 'started';
const EVENT_UPDATE = 'update';
const EVENT_COMPLETED = 'completed';
const EVENT_STOPPED = 'stopped';

///
/// 一个抽象类，用于访问Announce获取数据。
///
/// ```
abstract class Tracker {
  /// Tracker ID , usually use server host url to be its id.
  final String id;

  /// Torrent file info hash bytebuffer
  final Uint8List infoHashBuffer;

  /// Torrent file info hash string
  String _infoHash;

  /// server url;
  final Uri announceUrl;
  bool _stopped = true;

  /// 循环访问announce url的间隔时间，单位秒，默认值30分钟
  int _announceInterval = 30 * 60; // 30 minites

  /// 循环scrape数据的间隔时间，单位秒，默认1分钟
  int announceScrape = 1 * 60;

  final Set<void Function(PeerEvent)> _peerEventHandlers = {};

  final Set<void Function(dynamic error)> _announceErrorHandlers = {};

  final Set<void Function(int intervalTime)> _announceOverHandlers = {};

  Timer _announceTimer;

  bool _disposed = false;

  AnnounceOptionsProvider provider;

  Tracker(this.id, this.announceUrl, this.infoHashBuffer, {this.provider}) {
    assert(id != null, 'id cant be null');
    assert(announceUrl != null, 'announce url cant be null');
    assert(infoHashBuffer != null && infoHashBuffer.isNotEmpty,
        'info buffer cant be null or empty');
  }

  /// Torrent file info hash string
  String get infoHash {
    _infoHash ??= infoHashBuffer.fold('', (previousValue, byte) {
      var s = byte.toRadixString(16);
      if (s.length != 2) s = '0$s';
      return previousValue + s;
    });
    return _infoHash;
  }

  ///
  /// 开始循环发起announce访问。
  ///
  Future<bool> start([bool errorOrCancel = false]) async {
    if (isDisposed) throw Exception('This tracker was disposed');
    if (!_stopped) return false; // Stream.value(false);
    _stopped = false;
    return _intervalAnnounce(null, EVENT_STARTED, errorOrCancel);
  }

  void onAnnounceError(void Function(dynamic error) handler) {
    _announceErrorHandlers.add(handler);
  }

  void onPeerEvent(void Function(PeerEvent) handler) {
    _peerEventHandlers.add(handler);
  }

  void onAnnounceOver(void Function(int intervalTime) handler) {
    _announceOverHandlers.add(handler);
  }

  void _firePeerEvent(PeerEvent event) {
    _peerEventHandlers.forEach((handler) {
      Timer.run(() => handler(event));
    });
  }

  void _fireAnnounceError(dynamic error) {
    _announceErrorHandlers.forEach((handler) {
      Timer.run(() => handler(error));
    });
  }

  void _fireAnnounceOver(int intervalTime) {
    _announceOverHandlers.forEach((handler) {
      Timer.run(() => handler(intervalTime));
    });
  }

  ///
  /// 该方法会一直循环Announce，直到stopped属性为true。
  /// 每次循环访问的间隔时间是announceInterval，子类在实现announce方法的时候返回值需要加入interval值，
  /// 这里会比较返回值和现有值，如果不同会停止当前的Timer并重新生成一个新的循环间隔Timer
  ///
  /// 如果announce抛出异常，该循环不会停止,除非[errorOrCancel]设置位 `true`
  Future<bool> _intervalAnnounce(Timer timer, String event,
      [bool errorOrCancel = false]) async {
    if (isStopped) {
      timer?.cancel();
      return false;
    }
    PeerEvent result;
    try {
      result = await announce(event, await _announceOptions);
      result.eventType = event;
      _firePeerEvent(result);
    } catch (e) {
      _fireAnnounceError(e);
      if (errorOrCancel) {
        timer?.cancel();
        timer = null;
        _fireAnnounceOver(_announceInterval);
        return false;
      }
    }
    var interval;
    if (result != null && result is PeerEvent) {
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
    // debug:
    // if(announceUrl.host == 'tracker.gbitt.info'){
    //   print('here');
    // }
    interval ??= _announceInterval;
    if (timer == null || interval != _announceInterval) {
      timer?.cancel();
      _announceInterval = interval;
      // _announceInterval = 10; //test
      _announceTimer = Timer.periodic(Duration(seconds: _announceInterval),
          (timer) => _intervalAnnounce(timer, event));
    }
    _fireAnnounceOver(_announceInterval);
    return true;
  }

  bool get isDisposed => _disposed;

  Future dispose() async {
    _disposed = true;
    _clean();
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
      var opt = await provider.getOptions(announceUrl, infoHash);
      if (opt != null && opt.isNotEmpty) options = opt;
    }
    return options;
  }

  void _clean() {
    stopIntervalAnnounce();
    _peerEventHandlers.clear();
    _announceErrorHandlers.clear();
    _announceOverHandlers.clear();
  }

  void stopIntervalAnnounce() {
    _announceTimer?.cancel();
    _announceTimer = null;
  }

  ///
  /// 当突然停止需要调用该方法去通知`announce`。
  ///
  /// 该方法会调用一次`announce`，参数位`stopped`。
  ///
  /// [force] 是强制关闭标识，默认值为`false`。 如果为`true`，刚方法不会去调用`announce`方法
  /// 发送`stopped`请求，而是直接返回一个`null`
  Future<PeerEvent> stop([bool force = false]) async {
    if (isDisposed) throw Exception('This tracker was disposed');
    if (_stopped) return null;
    _clean();
    _stopped = true;
    if (force) {
      return null;
    }
    var re = await announce(EVENT_STOPPED, await _announceOptions);
    re.eventType = EVENT_STOPPED;
    _firePeerEvent(re);
    return re;
  }

  ///
  /// 当完成下载后需要调用该方法去通知announce。
  ///
  /// 该方法会调用一次announce，参数位completed。
  Future<PeerEvent> complete() async {
    if (isDisposed) throw Exception('This tracker was disposed');
    if (_stopped) return null;
    try {
      var re = await announce(EVENT_COMPLETED, await _announceOptions);
      re.eventType = EVENT_COMPLETED;
      _firePeerEvent(re);
      return re;
    } catch (e) {
      log('访问错误:', error: e, name: runtimeType.toString());
      return null;
    }
  }

  ///
  /// 访问announce url获取数据。
  ///
  /// 调用方法即可开始一次对Announce Url的访问，返回是一个Future，如果成功，则返回正常数据，如果访问过程中
  /// 有任何失败，比如解码失败、访问超时等，都会抛出异常。
  /// 参数eventType必须是started,stopped,completed中的一个，可以是null。
  ///
  /// 返回的数据应该是一个[PeerEvent]对象。如果该对象interval属性值不为空，并且该属性值和当前的循环间隔时间
  /// 不同，那么Tracker就会停止当前的Timer并重新创建一个Timer，间隔时间设置为返回对象中的interval值
  Future<PeerEvent> announce(String eventType, Map<String, dynamic> options);

  bool get isStopped {
    return _stopped;
  }
}

abstract class AnnounceOptionsProvider {
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash);
}
