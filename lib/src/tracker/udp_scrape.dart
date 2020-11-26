import 'dart:convert';
import 'dart:typed_data';

import 'udp_tracker_base.dart';

import 'scrape.dart';

/// Take a look : [UDP Scrape Specification](http://xbtt.sourceforge.net/udp_tracker_protocol.html)
class UDPScrape extends Scrape with UDPTrackerBase {
  UDPScrape(Uri uri) : super('${uri.host}:${uri.port}', uri);

  @override
  Future scrape() {
    return contactAnnouncer();
  }

  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId) {
    var list = <int>[];
    list.addAll(connectionId);
    list.addAll(ACTION_SCRAPE); // Action的类型，目前是scrapt,即2
    list.addAll(transcationId); // 会话ID
    var infos = infoHashSet;
    if (infos.isEmpty) throw Exception('infohash 不能位空');
    infos.forEach((info) {
      var encode = latin1.encode(info);
      list.addAll(encode);
    });
    return Uint8List.fromList(list);
  }

  @override
  dynamic processResponseData(Uint8List data, int action) {
    if (action != 2) throw Exception('返回数据中的Action不匹配');
    var view = ByteData.view(data.buffer);
    var result = {};
    var i = 0;
    for (var index = 8; index < data.length; index += 12, i++) {
      var r = {
        'complete': view.getUint32(index),
        'downloaded': view.getUint32(index + 4),
        'incomplete': view.getUint32(index + 8)
      };
      result[infoHashSet.elementAt(i)] = r;
    }
    return result;
  }

  @override
  Uri get uri => scrapeUrl;
}
