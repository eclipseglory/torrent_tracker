import 'dart:developer';

import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  var torrent = await Torrent.parse('example/test.torrent');

  var scrapeTracker = TorrentScrapeTracker();
  scrapeTracker.addScrapes(torrent.announces, torrent.infoHashBuffer);
  scrapeTracker.scrape(torrent.infoHashBuffer).listen((event) {
    print(event);
  }, onError: (e) => log('error:', error: e, name: 'MAIN'));
}
