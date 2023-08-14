import 'dart:typed_data';
import 'scraper_generator.dart';
import 'tracker/tracker_base.dart';

import 'package:dtorrent_common/dtorrent_common.dart';

/// Torrent scrape tracker
class TorrentScrapeTracker {
  ScraperGenerator? provider;
  TorrentScrapeTracker([this.provider]) {
    provider ??= ScraperGenerator.base();
  }
  final Map<Uri, Scrape> _scrapers = {};

  final Map<String, Set<Scrape>> _file2scrapeMap = {};

  Scrape? addScraper(Uri url, Uint8List infohash) {
    if (infohash.length != 20) {
      return null;
    }
    var scraper = _scrapers[url];
    if (scraper == null) {
      scraper = provider?.createScrape(url);
      if (scraper == null) return null;
      _scrapers[url] = scraper;
    }
    if (scraper.addInfoHash(infohash)) {
      var infoHashHex = transformBufferToHexString(infohash);
      var scrapeSet = _file2scrapeMap[infoHashHex];
      if (scrapeSet == null) {
        scrapeSet = <Scrape>{};
        _file2scrapeMap[infoHashHex] = scrapeSet;
      }
      scrapeSet.add(scraper);
    }

    return scraper;
  }

  List<Scrape> addScrapes(Iterable<Uri> announces, Uint8List infoHashBuffer) {
    var l = <Scrape>[];
    for (var url in announces) {
      var s = addScraper(url, infoHashBuffer);
      if (s != null) l.add(s);
    }
    return l;
  }

  Stream scrape(Uint8List infoHashBuffer) {
    return scrapeByInfoHashHexString(
        transformBufferToHexString(infoHashBuffer));
  }

  Stream scrapeByInfoHashHexString(String infoHash) {
    var scrapeSet = _file2scrapeMap[infoHash];
    if (scrapeSet != null && scrapeSet.isNotEmpty) {
      var futures = <Future>[];
      for (var scrape in scrapeSet) {
        futures.add(scrape.scrape({}));
      }
      return Stream.fromFutures(futures);
    }
    return Stream.empty();
  }

  Future scrapeByUrl(Uri url) {
    var scrape = _scrapers[url];
    if (scrape != null) return scrape.scrape({});
    return Future.value(false);
  }
}
