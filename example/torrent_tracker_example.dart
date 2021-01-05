import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:dartorrent_common/dartorrent_common.dart';

import 'package:torrent_tracker/src/torrent_announce_tracker.dart';
import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  // https://newtrackon.com/api/stable
  // Get more announces from `newtrackon` website
  var alist = <Uri>[];
  try {
    var url = Uri.parse('http://newtrackon.com/api/stable');
    var client = HttpClient();
    var request = await client.getUrl(url);
    var response = await request.close();
    var stream = await utf8.decoder.bind(response);
    await stream.forEach((element) {
      var ss = element.split('\n');
      ss.forEach((url) {
        if (url.isNotEmpty) {
          try {
            var r = Uri.parse(url);
            alist.add(r);
          } catch (e) {
            //
          }
        }
      });
    });
  } catch (e) {
    print(e);
  }
  var torrent = await Torrent.parse('example/test.torrent');
  var id = generatePeerId();
  var port = 55551;
  var provider = SimpleProvider(torrent, id, port);
  var peerAddress = <CompactAddress>{};

  /// Announce Track:
  try {
    var torrentTracker = TorrentAnnounceTracker(provider);
    torrentTracker.onTrackerDispose((source, reason) {
      // if (reason != null) log('Tracker disposed :', error: reason);
    });
    torrentTracker.onAnnounceError((source, error) {
      log('announce error:', error: error);
    });
    torrentTracker.onPeerEvent((source, event) {
      // print('${source.announceUrl} peer event: $event');
      peerAddress.addAll(event.peers);
      print('got ${peerAddress.length} peers');
    });

    torrentTracker.onAnnounceOver((source, time) {
      print('${source.announceUrl} announce over!: $time');
      source.dispose();
    });

    torrentTracker.runTrackers(torrent.announces, torrent.infoHashBuffer);
    torrentTracker.runTrackers(alist, torrent.infoHashBuffer);
    Timer(Duration(seconds: 30), () async {
      await torrentTracker.dispose();
      print(peerAddress);
    });
  } catch (e) {
    print(e);
  }

  /// Scrape
  var scrapeTracker = TorrentScrapeTracker();
  scrapeTracker.addScrapes(torrent.announces, torrent.infoHashBuffer);
  scrapeTracker.scrape(torrent.infoHashBuffer).listen((event) {
    print(event);
  }, onError: (e) => log('error:', error: e, name: 'MAIN'));
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
