import 'dart:typed_data';

import 'scrape_event.dart';

import '../utils.dart';

import 'udp_tracker_base.dart';

import 'scrape.dart';

/// Take a look : [UDP Scrape Specification](http://xbtt.sourceforge.net/udp_tracker_protocol.html)
class UDPScrape extends Scrape with UDPTrackerBase {
  UDPScrape(Uri uri) : super('${uri.host}:${uri.port}', uri);

  @override
  Future scrape(Map options) {
    return contactAnnouncer(options);
  }

  /// Scrape的时候要向remote发送的有：
  /// - Connection ID. 这个是在第一次连接后Remote返回的，已作为参数传入。
  /// - Action ，这里是2，意思是Scrape、
  /// - Transcation ID，第一次连接时就已经生成
  /// - [info hash] ，这可以是多个Torrent 文件的info hash
  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options) {
    var list = <int>[];
    list.addAll(connectionId);
    list.addAll(ACTION_SCRAPE); // Action的类型，目前是scrapt,即2
    list.addAll(transcationId); // 会话ID
    var infos = infoHashSet;
    if (infos.isEmpty) throw Exception('infohash 不能位空');
    infos.forEach((info) {
      list.addAll(info);
    });
    return Uint8List.fromList(list);
  }

  ///
  /// 处理从remote返回的scrape信息。
  ///
  /// 该信息是一组由complete,downloaded,incomplete组成的数据。
  @override
  dynamic processResponseData(Uint8List data, int action) {
    var event = ScrapeEvent(uri);
    if (action != 2) throw Exception('返回数据中的Action不匹配');
    var view = ByteData.view(data.buffer);
    var i = 0;
    for (var index = 8; index < data.length; index += 12, i++) {
      var file = ScrapeResult(
          transformBufferToHexString(infoHashSet.elementAt(i)),
          complete: view.getUint32(index),
          downloaded: view.getUint32(index + 4),
          incomplete: view.getUint32(index + 8));
      event.addFile(file.infoHash, file);
    }
    return event;
  }

  @override
  Uri get uri => scrapeUrl;

  @override
  void handleSocketDone() {
    // TODO: implement handleSocketDone
  }

  @override
  void handleSocketError(e) {
    // TODO: implement handleSocketError
  }
}
