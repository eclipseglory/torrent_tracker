import 'dart:async';

const EVENT_STARTED = 'started';
const EVENT_UPDATE = 'update';
const EVENT_COMPLETED = 'completed';
const EVENT_STOPPED = 'stopped';

///
/// 一个抽象类，用于访问Announce获取数据。
///
/// ```
abstract class Tracker {
  final String id;
  int port;
  dynamic hashInfo;
  final String peerId;
  final Uri announceUrl;
  int downloaded;
  int left;
  int uploaded;
  int compact;
  bool _stopped = false;
  int numwant;

  /// 循环访问announce url的间隔时间，单位秒，默认值30分钟
  int _announceInterval = 30 * 60; // 30 minites

  /// 循环scrape数据的间隔时间，单位秒，默认1分钟
  int announceScrape = 1 * 60;

  StreamController _announceSC;

  Timer _announceTimer;

  Tracker(this.id, this.announceUrl, this.peerId, this.hashInfo, this.port,
      {this.downloaded, this.left, this.uploaded, this.compact, this.numwant});

  ///
  /// 开始循环发起announce访问。
  ///
  /// 返回一个Stream，调用者可以利用listen方法监听返回结果以及发生的错误
  ///
  Stream start() {
    _stopped = false;
    _announceSC?.close();
    _announceSC = StreamController();
    _announceTimer?.cancel();
    _intervalAnnounce(null, EVENT_STARTED, _announceSC);
    return _announceSC.stream;
  }

  ///
  /// 该方法会一直循环Announce，直到stopped属性为true。
  /// 每次循环访问的间隔时间是announceInterval，子类在实现announce方法的时候返回值需要加入interval值，
  /// 这里会比较返回值和现有值，如果不同会停止当前的Timer并重新生成一个新的循环间隔Timer
  ///
  /// 如果announce抛出异常，该循环不会停止
  void _intervalAnnounce(Timer timer, String event, StreamController sc) async {
    try {
      if (isStopped) {
        timer?.cancel();
        return;
      }
      var result;
      try {
        result = await announce(event);
        sc.add(result);
      } catch (e) {
        sc.addError(e);
      }
      var interval;
      if (result != null) interval = result['interval'];
      interval ??= _announceInterval;
      if (timer == null || interval != _announceInterval) {
        timer?.cancel();
        _announceInterval = interval;
        // _announceInterval = 10; //test
        _announceTimer = Timer.periodic(Duration(seconds: _announceInterval),
            (timer) => _intervalAnnounce(timer, event, sc));
        return;
      }
    } catch (e) {
      sc.addError(e);
    }
    return;
  }

  void _clean() {
    _announceSC?.close();
    _announceTimer?.cancel();
    _announceTimer = null;
  }

  ///
  /// 当突然停止需要调用该方法去通知announce。
  ///
  /// 该方法会调用一次announce，参数位stopped。
  Future stop() {
    _clean();
    _stopped = true;
    return announce(EVENT_STOPPED);
  }

  ///
  /// 当完成下载后需要调用该方法去通知announce。
  ///
  /// 该方法会调用一次announce，参数位completed。该方法和stop是独立两个方法，如果需要释放资源等善后工作，子类必须复写该方法
  Future complete() {
    _clean();
    _stopped = true;
    return announce(EVENT_COMPLETED);
  }

  ///
  /// 访问announce url获取数据。
  ///
  /// 调用方法即可开始一次对Announce Url的访问，返回是一个Future，如果成功，则返回正常数据，如果访问过程中
  /// 有任何失败，比如解码失败、访问超时等，都会抛出异常。
  /// 参数eventType必须是started,stopped,completed中的一个，可以是null。
  Future announce(String eventType);

  bool get isStopped {
    return _stopped;
  }
}
