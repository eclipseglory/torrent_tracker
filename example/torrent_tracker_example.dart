import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:dartorrent_common/dartorrent_common.dart';

import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  var torrent = await Torrent.parse('example/test.torrent');

  var id = generatePeerId();
  var port = 55551;
  var provider = SimpleProvider(torrent, id, port, torrent.infoHash);
  var peerAddress = <CompactAddress>{};
  print(provider.torrent);

  /// Announce Track:
  try {
    var torrentTracker = TorrentAnnounceTracker(provider, maxRetryTime: 0);
    torrentTracker.onTrackerDispose((source, reason) {
      // if (reason != null && source is HttpTracker)
      log('Tracker disposed  , remain ${torrentTracker.trackersNum} :',
          error: reason);
    });
    torrentTracker.onAnnounceError((source, error) {
      // log('announce error:', error: error);
      // source.dispose(error);
    });
    torrentTracker.onPeerEvent((source, event) {
      // print('${source.announceUrl} peer event: $event');
      if (event == null) return;
      peerAddress.addAll(event.peers);
      source.dispose('Complete Announc');
      print('got ${peerAddress.length} peers');
    });

    torrentTracker.onAnnounceOver((source, time) {
      print('${source.announceUrl} announce over: $time');
      // source.dispose();
    });
    findPublicTrackers().listen((urls) {
      torrentTracker.runTrackers(urls, torrent.infoHashBuffer);
    });

    // Timer(Duration(seconds: 120), () async {
    //   await torrentTracker.stop(true);
    //   print('completed $peerAddress');
    // });
  } catch (e) {
    print(e);
  }

  /// Scrape
  // var scrapeTracker = TorrentScrapeTracker();
  // scrapeTracker.addScrapes(torrent.announces, torrent.infoHashBuffer);
  // scrapeTracker.scrape(torrent.infoHashBuffer).listen((event) {
  //   print(event);
  // }, onError: (e) => log('error:', error: e, name: 'MAIN'));
}

class SimpleProvider implements AnnounceOptionsProvider {
  SimpleProvider(this.torrent, this.peerId, this.port, this.infoHash);
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
  var id = '-MURLIN-$base64Str';
  return id;
}
