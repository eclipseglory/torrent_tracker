import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'peer_event.dart';
import 'http_tracker_base.dart';
import 'tracker.dart';

/// Torrent http/https tracker implement.
///
/// Torrent http tracker protocol specification :
/// [HTTP/HTTPS Tracker Protocol](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol).
///
class HttpTracker extends Tracker with HttpTrackerBase {
  String? _trackerId;
  String? _currentEvent;
  HttpTracker(Uri _uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super(
            'http:${_uri.host}:${_uri.port}${_uri.path}', _uri, infoHashBuffer,
            provider: provider);

  String? get currentTrackerId {
    return _trackerId;
  }

  String? get currentEvent {
    return _currentEvent;
  }

  @override
  Future<PeerEvent?> stop([bool force = false]) async {
    await close();
    var f = super.stop(force);
    return f;
  }

  @override
  Future<PeerEvent?> complete() async {
    await close();
    var f = super.complete();
    return f;
  }

  @override
  Future dispose([dynamic reason]) async {
    await close();
    return super.dispose(reason);
  }

  @override
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent =
        eventType; // 修改当前event，stop和complete也会调用该方法，所以要在这里进行记录当前event类型
    return httpGet<PeerEvent>(options);
  }

  ///
  /// 创建访问announce的URL string,
  /// 更多信息可以访问[HTTP/HTTPS Tracker Request Parameters](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_Request_Parameters)
  ///
  /// 关于访问的query参数：
  /// - compact : 我一直设位1
  /// - downloaded : 已经下载的字节数
  /// - uploaded : 上传字节数
  /// - left : 剩余未下载的字节数
  /// - numwant : 可选项。这里默认值是50，最好不要设为-1，访问一些地址对方会认为是非法数字
  /// - info_hash : 必填项。来自torrent文件。这里要注意，这里没有使用 *Uri* 的urlencode来获取，
  /// 是因为该类在生成query string的时候采用的是UTF-8编码,这导致无法具有一些特殊文字的info_hash无法正确编码，所以这里手动处理一下。
  /// - port ： 必填项。TCP监听端口
  /// - peer_id ：必填项。随机生成的一个20长度的字符串，要采用query string编码，但目前我使用的都是数字和英文字母，所以直接使用
  /// - event ：必须是stopped,started,completed中的一个。按照协议来做，第一次访问必须是started。如果不指定，对方会认为是一次普通的announce访问
  /// - trackerid : 可选项，如果上一次请求包含了trackerid，那就应该设置。有些response里会包含tracker id。有些response会携带trackerid，这时候我就会设置该字段。
  /// - ip ：可选项
  /// - key ：可选项
  /// - no_peer_id : 如果compact指定，则该字段会被忽略。我在这里的compact一直都是1，所以就没有设该值
  ///
  @override
  Map<String, String> generateQueryParameters(Map<String, dynamic> options) {
    var params = <String, String>{};
    params['compact'] = options['compact'].toString();
    params['downloaded'] = options['downloaded'].toString();
    params['uploaded'] = options['uploaded'].toString();
    params['left'] = options['left'].toString();
    params['numwant'] = options['numwant'].toString();
    // infohash value usually can not be decode by utf8, because some special character,
    // so I transform them with String.fromCharCodes , when transform them to the query component, use latin1 encoding
    params['info_hash'] = Uri.encodeQueryComponent(
        String.fromCharCodes(infoHashBuffer),
        encoding: latin1);
    params['port'] = options['port'].toString();
    params['peer_id'] = options['peerId'];
    var event = currentEvent;
    if (event != null) {
      params['event'] = event;
    } else {
      params['event'] = EVENT_STARTED;
    }
    if (currentTrackerId != null) params['trackerid'] = currentTrackerId!;
    // params['no_peer_id']
    // params['ip'] ; 可选
    // params['key'] ; 可选
    return params;
  }

  ///
  /// Decode the return bytebuffer with bencoder.
  ///
  /// - Get the 'interval' value , and make sure the return Map contains it(or null), because the Tracker
  /// will check the return Map , if it has 'interval' value , Tracker will update the interval timer.
  /// - If it has 'tracker id' , need to store it , use it next time.
  /// - parse 'peers' informations. the peers usually is a List<int> , need to parse it to 'n.n.n.n:p' formate
  /// ip address.
  /// - Sometimes , the remote will return 'failer reason', then need to throw a exception
  @override
  PeerEvent processResponseData(Uint8List data) {
    var result = decode(data) as Map;
    // You cuo wu , jiu tao chu qu
    if (result['failure reason'] != null) {
      var errorMsg = String.fromCharCodes(result['failure reason']);
      throw errorMsg;
    }
    // If 'tracker id' is existed, record it
    if (result['tracker id'] != null) {
      _trackerId = result['tracker id'];
    }

    var event = PeerEvent(infoHash, url);
    result.forEach((key, value) {
      if (key == 'min interval') {
        event.minInterval = value;
        return;
      }
      if (key == 'interval') {
        event.interval = value;
        return;
      }
      if (key == 'warning message' && value != null) {
        event.warning = String.fromCharCodes(value);
        return;
      }
      if (key == 'complete') {
        event.complete = value;
        return;
      }
      if (key == 'incomplete') {
        event.incomplete = value;
        return;
      }
      if (key == 'downloaded') {
        event.downloaded = value;
        return;
      }
      if (key == 'peers' && value != null) {
        _fillPeers(event, value);
        return;
      }
      // BEP0048
      if (key == 'peers6' && value != null) {
        _fillPeers(event, value, InternetAddressType.IPv6);
        return;
      }
      // record the values don't process
      event.setInfo(key, value);
    });
    return event;
  }

  void _fillPeers(PeerEvent event, dynamic value,
      [InternetAddressType type = InternetAddressType.IPv4]) {
    if (value is Uint8List) {
      if (type == InternetAddressType.IPv6) {
        try {
          var peers = CompactAddress.parseIPv6Addresses(value);
          for (var peer in peers) {
            event.addPeer(peer);
          }
        } catch (e) {
          //
        }
      } else if (type == InternetAddressType.IPv4) {
        try {
          var peers = CompactAddress.parseIPv4Addresses(value);
          for (var peer in peers) {
            event.addPeer(peer);
          }
        } catch (e) {
          //
        }
      }
    } else {
      if (value is List) {
        for (var peer in value) {
          var ip = peer['ip'];
          var port = peer['port'];
          var address = InternetAddress.tryParse(ip);
          if (address != null) {
            try {
              event.addPeer(CompactAddress(address, port));
            } catch (e) {
              log('parse peer address error',
                  error: e, name: runtimeType.toString());
            }
          }
        }
      }
    }
  }

  @override
  Uri get url => announceUrl;
}
