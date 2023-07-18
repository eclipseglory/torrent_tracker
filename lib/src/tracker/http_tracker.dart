import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'peer_event.dart';
import 'http_tracker_base.dart';
import 'tracker.dart';

/// Torrent http/https tracker implement.
///
/// Torrent http tracker protocol specification :
/// [HTTP/HTTPS Tracker Protocol](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol).
///
class HttpTracker extends Tracker with HttpTrackerBase {
  String? _trackerId;
  String? _currentEvent;
  HttpTracker(Uri _uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super(
            'http:${_uri.host}:${_uri.port}${_uri.path}', _uri, infoHashBuffer,
            provider: provider);

  String? get currentTrackerId {
    return _trackerId;
  }

  String? get currentEvent {
    return _currentEvent;
  }

  @override
  Future<PeerEvent?> stop([bool force = false]) async {
    await close();
    var f = super.stop(force);
    return f;
  }

  @override
  Future<PeerEvent?> complete() async {
    await close();
    var f = super.complete();
    return f;
  }

  @override
  Future dispose([dynamic reason]) async {
    await close();
    return super.dispose(reason);
  }

  @override
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent =
        eventType; // save the current event, stop and complete will also call this method, so the current event type should be recorded here
    return httpGet<PeerEvent>(options);
  }

  ///
  /// Create an access URL string for 'announce'.
  /// For more information, visit [HTTP/HTTPS Tracker Request Parameters](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_Request_Parameters)
  ///
  /// Regarding the query parameters for access:
  /// - compact: I keep setting bit 1.
  /// - downloaded: The number of bytes downloaded.
  /// - uploaded: The number of bytes uploaded.
  /// - left: The number of bytes left to download.
  /// - numwant: Optional. The default value here is 50, it's better not to set it to -1 as some addresses may consider it an illegal number.
  /// - info_hash: Required. Comes from the torrent file. Note that we don't use Uri's urlencode to obtain it because this class uses UTF-8 encoding when generating the query string, which causes issues with correctly encoding some special characters in the info_hash. So here, we handle it manually.
  /// - port: Required. TCP listening port.
  /// - peer_id: Required. A randomly generated string of 20 characters. It should be query string encoded, but currently, I use only digits and alphabets, so I directly use it.
  /// - event: Must be one of "stopped," "started," or "completed." According to the protocol, the first visit must be "started." If not specified, the other party will consider it a regular announce visit.
  /// - trackerid: Optional. If the previous request contained a trackerid, it should be set. Some responses may include a tracker ID, and if so, I will set this field.
  /// - ip: Optional.
  /// - key: Optional.
  /// - no_peer_id: If compact is specified, this field will be ignored. I always set compact to 1 here, so I don't set this value.
  ///
  @override
  Map<String, String> generateQueryParameters(Map<String, dynamic> options) {
    var params = <String, String>{};
    params['compact'] = options['compact'].toString();
    params['downloaded'] = options['downloaded'].toString();
    params['uploaded'] = options['uploaded'].toString();
    params['left'] = options['left'].toString();
    params['numwant'] = options['numwant'].toString();
    // infohash value usually can not be decode by utf8, because some special character,
    // so I transform them with String.fromCharCodes , when transform them to the query component, use latin1 encoding
    params['info_hash'] = Uri.encodeQueryComponent(
        String.fromCharCodes(infoHashBuffer),
        encoding: latin1);
    params['port'] = options['port'].toString();
    params['peer_id'] = options['peerId'];
    var event = currentEvent;
    if (event != null) {
      params['event'] = event;
    } else {
      params['event'] = EVENT_STARTED;
    }
    if (currentTrackerId != null) params['trackerid'] = currentTrackerId!;
    // params['no_peer_id']
    // params['ip'] ; optional
    // params['key'] ; optional
    return params;
  }

  ///
  /// Decode the return bytebuffer with bencoder.
  ///
  /// - Get the 'interval' value , and make sure the return Map contains it(or null), because the Tracker
  /// will check the return Map , if it has 'interval' value , Tracker will update the interval timer.
  /// - If it has 'tracker id' , need to store it , use it next time.
  /// - parse 'peers' informations. the peers usually is a List<int> , need to parse it to 'n.n.n.n:p' formate
  /// ip address.
  /// - Sometimes , the remote will return 'failer reason', then need to throw a exception
  @override
  PeerEvent processResponseData(Uint8List data) {
    var result = decode(data) as Map;
    // You cuo wu , jiu tao chu qu
    if (result['failure reason'] != null) {
      var errorMsg = String.fromCharCodes(result['failure reason']);
      throw errorMsg;
    }
    // If 'tracker id' is existed, record it
    if (result['tracker id'] != null) {
      _trackerId = result['tracker id'];
    }

    var event = PeerEvent(infoHash, url);
    result.forEach((key, value) {
      if (key == 'min interval') {
        event.minInterval = value;
        return;
      }
      if (key == 'interval') {
        event.interval = value;
        return;
      }
      if (key == 'warning message' && value != null) {
        event.warning = String.fromCharCodes(value);
        return;
      }
      if (key == 'complete') {
        event.complete = value;
        return;
      }
      if (key == 'incomplete') {
        event.incomplete = value;
        return;
      }
      if (key == 'downloaded') {
        event.downloaded = value;
        return;
      }
      if (key == 'peers' && value != null) {
        _fillPeers(event, value);
        return;
      }
      // BEP0048
      if (key == 'peers6' && value != null) {
        _fillPeers(event, value, InternetAddressType.IPv6);
        return;
      }
      // record the values don't process
      event.setInfo(key, value);
    });
    return event;
  }

  void _fillPeers(PeerEvent event, dynamic value,
      [InternetAddressType type = InternetAddressType.IPv4]) {
    if (value is Uint8List) {
      if (type == InternetAddressType.IPv6) {
        try {
          var peers = CompactAddress.parseIPv6Addresses(value);
          for (var peer in peers) {
            event.addPeer(peer);
          }
        } catch (e) {
          //
        }
      } else if (type == InternetAddressType.IPv4) {
        try {
          var peers = CompactAddress.parseIPv4Addresses(value);
          for (var peer in peers) {
            event.addPeer(peer);
          }
        } catch (e) {
          //
        }
      }
    } else {
      if (value is List) {
        for (var peer in value) {
          var ip = peer['ip'];
          var port = peer['port'];
          var address = InternetAddress.tryParse(ip);
          if (address != null) {
            try {
              event.addPeer(CompactAddress(address, port));
            } catch (e) {
              log('parse peer address error',
                  error: e, name: runtimeType.toString());
            }
          }
        }
      }
    }
  }

  @override
  Uri get url => announceUrl;
}
