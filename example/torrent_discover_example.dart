import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:torrent_tracker/src/torrent_scrape_tracker.dart';
import 'package:torrent_tracker/src/torrent_announce_tracker.dart';
import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_tracker/src/tracker/peer_event.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  var torrent = await Torrent.parse('example/test.torrent');
  var id = generatePeerId();
  var port = 55551;
  var provider = SimpleProvider(torrent, id, port);
  try {
    var torrentTracker = TorrentAnnounceTracker(
        torrent.announces.toList(), torrent.infoHashBuffer, provider);

    // var stream = torrentTracker.start();
    // stream.listen((event) {
    //   if (event['event'] is PeerEvent) {
    //     log(event['event'].toString());
    //     var id = event['id'];
    //     torrentTracker.stopTracker(id, true);
    //   }
    // }, onError: (e) async {
    //   var id = e['id'];
    //   var r;
    //   try {
    //     r = await torrentTracker.stopTracker(id, true);
    //   } catch (error) {
    //     r = error;
    //   }
    //   log('发生错误,close it,get response: $r', error: e['error']);
    // }, onDone: () => print('Torrent Tracker Closed'));

    var scrapeTracker = TorrentScrapeTracker();
    scrapeTracker.createScrapeFromAnnounces(
        torrent.announces.toList(), torrent.infoHashBuffer);
    // print(scrapeTracker);
    scrapeTracker.scrape().listen((event) {
      print(event);
    }, onError: (e) => log('error:', error: e));
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

Uint8List randomBytes(count) {
  var random = math.Random();
  var bytes = Uint8List(count);
  for (var i = 0; i < count; i++) {
    bytes[i] = random.nextInt(254);
  }
  return bytes;
}

String generatePeerId() {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = '-MURLIN-' + base64Str;
  return id;
}
