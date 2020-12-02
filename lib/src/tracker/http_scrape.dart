import 'dart:convert';
import 'dart:typed_data';
import 'package:bencode_dart/bencode_dart.dart' as bencode;
import 'scrape_event.dart';
import '../utils.dart';

import 'http_tracker_base.dart';
import 'scrape.dart';

///
/// Torrent http scrape.
///
/// extends from Scrape class
class HttpScrape extends Scrape with HttpTrackerBase {
  HttpScrape(Uri scrapeUrl)
      : super('${scrapeUrl.origin}${scrapeUrl.path}', scrapeUrl);

  @override
  Map<String, dynamic> generateQueryParameters(Map<String, dynamic> options) {
    if (infoHashSet.isEmpty) return null;
    var infos = [];
    // infohash value usually can not be decode by utf8, because some special character,
    // so I transform them with String.fromCharCodes , when transform them to the query component, use latin1 encoding
    infoHashSet.forEach((infoHash) {
      var query = Uri.encodeQueryComponent(String.fromCharCodes(infoHash),
          encoding: latin1);
      infos.add(query);
    });
    return {'info_hash': infos};
  }

  @override
  dynamic processResponseData(Uint8List data) {
    var result = bencode.decode(data) as Map;
    if (result['failure reason'] != null) {
      throw Exception(String.fromCharCodes(result['failure reason']));
    }
    var event = ScrapeEvent(url);
    // 把file的key值转成Hex
    // var files = <String, Map>{};
    result.forEach((key, value) {
      if (key == 'files') {
        var list = value;
        for (var key in list.keys) {
          var fileHash = transformBufferToHexString((key as String).codeUnits);
          var fileInfo = list[key] as Map;
          var file = ScrapeResult(fileHash);
          fileInfo.forEach((key, value) {
            if (key == 'complete') {
              file.complete = value;
              return;
            }
            if (key == 'incomplete') {
              file.incomplete = value;
              return;
            }
            if (key == 'downloaded') {
              file.downloaded = value;
              return;
            }
            if (key == 'name') {
              file.name = value;
              return;
            }
            file.setInfo(key, value);
          });
          event.addFile(fileHash, file);
        }
      } else {
        event.setInfo(key, value);
      }
    });
    return event;
    // if (result['files'] != null) {
    //   var list = result['files'];
    //   for (var key in list.keys) {
    //     files[transformBufferToHexString((key as String).codeUnits)] =
    //         list[key];
    //   }
    //   result['files'] = files;
    // }
    // return result;
  }

  @override
  Future scrape(Map options) async {
    // 目前scrape是不需要提供访问参数的
    try {
      var re = await httpGet(options);
      return re;
    } catch (e) {
      rethrow;
    } finally {
      clean();
    }
  }

  @override
  Uri get url => scrapeUrl;
}
