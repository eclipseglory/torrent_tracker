import 'dart:typed_data';

import 'scraper_generator.dart';
import 'tracker/tracker_base.dart';

import 'package:dartorrent_common/dartorrent_common.dart';

/// Torrent scrape tracker
class TorrentScrapeTracker {
  ScraperGenerator provider;
  TorrentScrapeTracker([this.provider]) {
    provider ??= ScraperGenerator.base();
  }
  final Map<String, Scrape> _scrapers = {};

  final Map<String, Set<Scrape>> _file2scrapeMap = {};

  String _getKeyFromUrl(Uri url) {
    var key = url.toString();
    if (url.isScheme('udp')) {
      key = '${url.host}:${url.port}';
    }
    if (url.isScheme('http') || url.isScheme('https')) {
      key = '${url.origin}${url.path}';
    }
    return key;
  }

  Scrape addTorrent(Uri announceUrl, Uint8List infoHashBuffer) {
    var key = _getKeyFromUrl(announceUrl);
    var scraper = _scrapers[key];
    if (scraper == null) {
      scraper = provider.createScrape(announceUrl);
      if (scraper == null) return null;
      _scrapers[key] = scraper;
    }
    if (scraper.addInfoHash(infoHashBuffer)) {
      var infoHash = transformBufferToHexString(infoHashBuffer);
      var scrapeSet = _file2scrapeMap[infoHash];
      if (scrapeSet == null) {
        scrapeSet = <Scrape>{};
        _file2scrapeMap[infoHash] = scrapeSet;
      }
      scrapeSet.add(scraper);
    }

    return scraper;
  }

  List<Scrape> createScrapeFromAnnounces(
      List<Uri> announces, Uint8List infoHashBuffer) {
    var list = <Scrape>[];
    announces.forEach((url) {
      var s = addTorrent(url, infoHashBuffer);
      if (s != null) list.add(s);
    });
    return list;
  }

  Stream scrapeFileByInfohashBuffer(Uint8List infoHashBuffer) {
    return scrapeFileByInfohash(transformBufferToHexString(infoHashBuffer));
  }

  Stream scrapeFileByInfohash(String infoHash) {
    var scrapeSet = _file2scrapeMap[infoHash];
    if (scrapeSet != null && scrapeSet.isNotEmpty) {
      var futures = <Future>[];
      scrapeSet.forEach((scrape) {
        futures.add(scrape.scrape({}));
      });
      return Stream.fromFutures(futures);
    }
    return Stream.empty();
  }

  Future scrapeByUrl(Uri url) {
    var key = _getKeyFromUrl(url);
    var scrape = _scrapers[key];
    if (scrape != null) return scrape.scrape({});
    return Future.value(false);
  }

  Stream scrape() {
    if (_scrapers.isEmpty) return Stream.empty();
    var futures = <Future>[];
    _scrapers.values.forEach((scrape) {
      futures.add(scrape.scrape({}));
    });
    return Stream.fromFutures(futures);
  }
}
