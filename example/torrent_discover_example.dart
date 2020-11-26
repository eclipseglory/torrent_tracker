import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:async/async.dart';

import 'package:torrent_discover/torrent_discover.dart';
import 'package:torrent_parser/torrent_parser.dart';

void main() async {
  var torrent = await TorrentParser.parse('example/test.torrent');
  var id = generatePeerId();
  var idbytes = utf8.encode(id);
  var discover = PeerDiscover('id', torrent, id, 55551, 0, 0);
  var stream = discover.start();
  stream.listen((event) {
    // print(event);
  }, onError: (e) {
    // print(e);
  });
  // print(torrent);

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
