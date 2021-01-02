import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dartorrent_common/dartorrent_common.dart';

import 'package:torrent_tracker/src/torrent_scrape_tracker.dart';
import 'package:torrent_tracker/src/torrent_announce_tracker.dart';
import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  // var test = () async {
  //   var c = Completer();
  //   throw 'e';
  //   return c.future;
  // };

  // test().then((value) => null).catchError((e) {
  //   print(e);
  // });

  // exit(1);

  var torrent = await Torrent.parse('example/test.torrent');
  var id = generatePeerId();
  var port = 55551;
  var provider = SimpleProvider(torrent, id, port);
  try {
    var torrentTracker =
        TorrentAnnounceTracker(torrent.infoHashBuffer, provider);
    torrentTracker.onAnnounceError((source, error) {
      log('announce error:', error: error);
    });
    torrentTracker.onPeerEvent((source, event) {
      print('${source.announceUrl} peer event: $event');
    });

    torrentTracker.onAnnounceOver((source, time) {
      print('${source.announceUrl} announce over!: $time');
      source.dispose();
    });

    // torrentTracker.onAllAnnounceOver((total) {
    //   log('全部走一遍，共有 $total trackers');
    // });
    torrentTracker.addAnnounces(torrent.announces.toList(), false);

    torrentTracker.startAll();

    // var scrapeTracker = TorrentScrapeTracker();
    // scrapeTracker.createScrapeFromAnnounces(
    //     torrent.announces.toList(), torrent.infoHashBuffer);
    // // print(scrapeTracker);
    // scrapeTracker.scrape().listen((event) {
    //   print(event);
    // }, onError: (e) => log('error:', error: e, name: 'MAIN'));
  } catch (e) {
    print(e);
  }
}

class SimpleProvider implements AnnounceOptionsProvider {
  SimpleProvider(this.torrent, this.peerId, this.port);
  String peerId;
  int port;
  String infoHash;
  Torrent torrent;
  int compact = 1;
  int numwant = 50;

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    return Future.value({
      'downloaded': 0,
      'uploaded': 0,
      'left': torrent.length,
      'compact': compact,
      'numwant': numwant,
      'peerId': peerId,
      'port': port
    });
  }
}

String generatePeerId() {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = '-MURLIN-' + base64Str;
  return id;
}
