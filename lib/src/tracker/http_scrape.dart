import 'dart:convert';
import 'dart:typed_data';
import 'package:bencode_dart/bencode.dart' as bencode;

import 'http_tracker_base.dart';
import 'scrape.dart';

class HttpScrape extends Scrape with HttpTrackerBase {
  HttpScrape(Uri scrapeUrl)
      : super('${scrapeUrl.origin}${scrapeUrl.path}', scrapeUrl);

  @override
  Map<String, dynamic> generateQueryParameters() {
    if (infoHashSet.isEmpty) return null;
    var infos = [];
    infoHashSet.forEach((hashStr) {
      infos.add(Uri.encodeQueryComponent(hashStr, encoding: latin1));
    });
    //X%8E%11%29%AEV8k%02%C6%7D%A8%FA%3F%0E%04%02%5D%03%1D
    return {'info_hash': infos};
  }

  @override
  dynamic processResponseData(Uint8List data) {
    // try {
    //   var str = utf8.decode(data);
    //   print(str);
    // } catch (e) {
    //   print(e);
    // }
    var result = bencode.decode(data);
    return result;
  }

  @override
  Future scrape() {
    return httpGet();
  }

  @override
  Uri get url => scrapeUrl;
}
