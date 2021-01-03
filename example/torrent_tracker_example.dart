import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:dartorrent_common/dartorrent_common.dart';

import 'package:torrent_tracker/src/torrent_announce_tracker.dart';
import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:torrent_model/torrent_model.dart';

void main() async {
  var torrent = await Torrent.parse('example/test.torrent');
  var id = generatePeerId();
  var port = 55551;
  var provider = SimpleProvider(torrent, id, port);
  try {
    var torrentTracker = TorrentAnnounceTracker(provider);
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

    torrentTracker.runTrackers(torrent.announces, torrent.infoHashBuffer);
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
