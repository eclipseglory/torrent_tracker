import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bencode_dart/bencode.dart';
import 'http_tracker_base.dart';
import 'tracker.dart';
import '../utils.dart' as utils;

/// Torrent http/https tracker implement.
///
/// Torrent http tracker protocol specification :
/// [HTTP/HTTPS Tracker Protocol](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol).
///
class HttpTracker extends Tracker with HttpTrackerBase {
  String _trackerId;
  String _currentEvent;
  HttpTracker(Uri _uri, String peerId, String hashInfo, int port,
      {int downloaded,
      int left,
      int uploaded,
      int compact = 1,
      int numwant = 50})
      : super('${_uri.origin}${_uri.path}', _uri, peerId, hashInfo, port,
            downloaded: downloaded,
            left: left,
            uploaded: uploaded,
            compact: compact,
            numwant: numwant);

  String get currentTrackerId {
    return _trackerId;
  }

  String get currentEvent {
    return _currentEvent;
  }

  @override
  Future stop() {
    clean();
    return super.stop();
  }

  @override
  Future complete() {
    clean();
    return super.complete();
  }

  @override
  Future announce(String event) {
    _currentEvent = event; // 修改当前event，stop和complete也会调用该方法，所以要在这里进行记录当前event类型
    return httpGet();
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
  Map<String, String> generateQueryParameters() {
    var params = <String, String>{};
    params['compact'] = compact.toString();
    params['downloaded'] = downloaded.toString();
    params['uploaded'] = uploaded.toString();
    params['left'] = left.toString();
    params['numwant'] = (numwant != null) ? numwant.toString() : '-1';
    params['info_hash'] = Uri.encodeQueryComponent(hashInfo, encoding: latin1);
    params['port'] = port.toString();
    params['peer_id'] = peerId;
    var event = currentEvent;
    if (event != null) {
      params['event'] = event;
    } else {
      params['event'] = EVENT_STARTED;
    }
    if (currentTrackerId != null) params['trackerid'] = currentTrackerId;
    // params['no_peer_id']
    // params['ip'] = peerId; 可选
    // params['key'] = peerId; 可选
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
  dynamic processResponseData(Uint8List data) {
    var result = decode(data) as Map;

    if (result['min interval'] != null) {
      if (result['interval'] != null) {
        // 取最小的值作为时间间隔
        result['interval'] =
            math.min<int>(result['min interval'], result['interval']);
      } else {
        result['interval'] = result['min interval'];
      }
    }
    if (result['failure reason'] != null) {
      var errorMsg = utf8.decode(result['failure reason']);
      log('得到对方返回的错误信息',
          name: runtimeType.toString(), time: DateTime.now(), error: errorMsg);
      throw Exception(errorMsg);
    }
    if (result['warning message'] != null) {
      result['warning message'] = utf8.decode(result['warning message']);
    }
    if (result['tracker id'] != null) {
      _trackerId = result['tracker id'];
    }
    if (result['peers'] != null) {
      if (result['peers'] is Uint8List) {
        result['peers'] = utils.getPeerIPv4List(result['peers']);
      }
    }
    if (result['peers6'] != null) {
      //   TODO 实现IPv6
    }

    // 剔除一些没必要返回的信息
    result.removeWhere((key, value) {
      return (key == 'min interval' || key == 'tracker id');
    });
    log('成功从 $announceUrl 获取数据 : $result',
        name: runtimeType.toString(), time: DateTime.now());
    return result;
  }

  @override
  Uri get url => announceUrl;
}
