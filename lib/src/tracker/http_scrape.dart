import 'dart:convert';
import 'dart:typed_data';
import 'package:bencode_dart/bencode.dart' as bencode;

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
  Map<String, dynamic> generateQueryParameters() {
    if (infoHashSet.isEmpty) return null;
    var infos = [];
    infoHashSet.forEach((hashStr) {
      infos.add(Uri.encodeQueryComponent(hashStr, encoding: latin1));
    });
    return {'info_hash': infos};
  }

  @override
  dynamic processResponseData(Uint8List data) {
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
