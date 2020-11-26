import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:torrent_discover/src/tracker/http_scrape.dart';
import 'package:torrent_discover/src/tracker/http_tracker_base.dart';
import 'package:torrent_discover/src/tracker/scrape.dart';
import 'package:torrent_discover/src/tracker/udp_scrape.dart';
import 'package:torrent_discover/src/utils.dart';

import 'tracker/http_tracker.dart';
import 'tracker/tracker.dart';
import 'tracker/udp_tracker.dart';

class PeerDiscover {
  final String id;
  Map decodedTorrent;
  int port;
  final String peerId;
  int downloaded;
  int uploaded;
  String infoBufferStr;
  StreamController _trackerController;

  final _trackerMap = <String, Tracker>{};
  PeerDiscover(this.id, this.decodedTorrent, this.peerId, this.port,
      this.downloaded, this.uploaded) {
    var infoHashBuffer = decodedTorrent['infoHashBuffer'];
    infoBufferStr = latin1.decode(infoHashBuffer);
  }

  Stream start() {
    var announceList = decodedTorrent['announce'];
    if (announceList == null || announceList.isEmpty) return Stream.empty();
    _trackerController = StreamController();
    var stream = _trackerController.stream;
    var scrapeList = <Scrape>[];
    var httpScrapeList = <Scrape>[];
    announceList.forEach((url) {
      var uri = Uri.parse(url);
      var tracker = _createTracker(uri);
      if (tracker != null && _trackerMap[tracker.id] == null) {
        _trackerMap[tracker.id] = tracker;
      }
      if (uri.isScheme('udp')) {
        var udpScrape = UDPScrape(uri);
        udpScrape.addInfoHash(infoBufferStr);
        scrapeList.add(udpScrape);
      }
      if (uri.isScheme('http') || uri.isScheme('https')) {
        var scrapeUrl = transformToScrapeUrl(uri.toString());
        if (scrapeUrl != null) {
          var scrape = HttpScrape(Uri.parse(scrapeUrl));
          scrape.addInfoHash(infoBufferStr);
          httpScrapeList.add(scrape);
        }
      }
    });
    print('you ${httpScrapeList.length}');
    var i = 0;
    // httpScrapeList.forEach((scrape) {
    //   scrape.scrape().then((r) => print(r)).catchError((e) {
    //     print('access ${scrape.id} chucuo : $e');
    //   }).whenComplete(() {
    //     (scrape as HttpTrackerBase).clean();
    //     i++;
    //     print(i);
    //   });
    // });
    // scrapeList.forEach((scrape) {
    //   scrape.scrape().then((r) => print(r)).catchError((e) => print(e));
    // });
    var group = StreamGroup();
    for (var key in _trackerMap.keys) {
      var tracker = _trackerMap[key];
      group.add(tracker.start());
      // _trackerController.addStream(tracker.start());
    }
    return group.stream;
  }

  void stop() {
    for (var id in _trackerMap.keys) {
      _trackerMap[id].stop();
    }
    _trackerMap.clear();
    _trackerController?.close()?.then((event) => _trackerController = null);
  }

  Tracker _createTracker(Uri uri) {
    var left = decodedTorrent['length'] - downloaded;
    if (uri.isScheme('http') || uri.isScheme('https')) {
      return HttpTracker(uri, peerId, infoBufferStr, port,
          downloaded: downloaded, uploaded: uploaded, left: left, compact: 1);
    }
    // if (uri.isScheme('udp')) {
    //   return UDPTracker(uri, peerId, decodedTorrent['infoHashBuffer'], port,
    //       downloaded: downloaded, uploaded: uploaded, left: left, compact: 1);
    // }
    return null;
  }

  void updateTracker(downloaded, uploaded, left) {
    for (var id in _trackerMap.keys) {
      var tracker = _trackerMap[id];
      tracker.downloaded = downloaded;
      tracker.uploaded = uploaded;
      tracker.left = tracker.left;
    }
  }
}
