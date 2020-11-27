import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'udp_tracker_base.dart';
import '../utils.dart';

import 'tracker.dart';

class UDPTracker extends Tracker with UDPTrackerBase {
  String _currentEvent;
  UDPTracker(Uri _uri, String peerId, Uint8List hashInfoBuffer, int port,
      {int downloaded,
      int left,
      int uploaded,
      int compact = 1,
      int numwant = 50})
      : super('${_uri.host}:${_uri.port}', _uri, peerId, hashInfoBuffer, port,
            downloaded: downloaded,
            left: left,
            uploaded: uploaded,
            compact: compact,
            numwant: numwant);

  String get currentEvent {
    return _currentEvent;
  }

  @override
  Uri get uri => announceUrl;

  @override
  Future announce(String eventType) {
    _currentEvent = eventType;
    return contactAnnouncer();
  }

  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId) {
    var list = <int>[];
    list.addAll(connectionId);
    list.addAll(ACTION_ANNOUNCE); // Action的类型，目前是announce,即1
    list.addAll(transcationId); // 会话ID
    list.addAll(hashInfo);
    list.addAll(utf8.encode(peerId));
    list.addAll(num2Uint64List(downloaded));
    list.addAll(num2Uint64List(left));
    list.addAll(num2Uint64List(uploaded));
    var event = EVENTS[currentEvent];
    event ??= 0;
    list.addAll(num2Uint32List(event)); // 这里是event类型
    list.addAll(num2Uint32List(0)); // 这里是ip地址，默认0
    list.addAll(num2Uint32List(0)); // 这里是keym,默认0
    list.addAll(num2Uint32List(numwant ?? -1)); // 这里是num_want,默认-1
    list.addAll(num2Uint16List(port)); // 这里是TCP的端口
    return Uint8List.fromList(list);
  }

  @override
  dynamic processResponseData(Uint8List data, int action) {
    if (data.length < 20) {
      // 数据不正确
      log('返回数据不正确', error: '长度不对', name: runtimeType.toString());
      throw Exception('announce data is wrong , from $announceUrl');
    }
    var view = ByteData.view(data.buffer);
    var interval = view.getUint32(8);
    var leechers = view.getUint32(16);
    var seeders = view.getUint32(12);
    var peers;
    try {
      peers = getPeerIPv4List(data.sublist(20));
    } catch (e) {
      // 容错
    }
    return {
      'interval': interval,
      'incomplete': leechers,
      'complete': seeders,
      'peers': peers,
      'url': announceUrl
    };
  }
}
