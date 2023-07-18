import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartorrent_common/dartorrent_common.dart';

import 'peer_event.dart';

import 'udp_tracker_base.dart';
import '../utils.dart';

import 'tracker.dart';

/// UDP Tracker
class UDPTracker extends Tracker with UDPTrackerBase {
  String? _currentEvent;
  UDPTracker(Uri _uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super('udp:${_uri.host}:${_uri.port}', _uri, infoHashBuffer,
            provider: provider);
  String? get currentEvent {
    return _currentEvent;
  }

  @override
  Future<List<CompactAddress>?> get addresses async {
    try {
      var ips = await InternetAddress.lookup(announceUrl.host);
      var l = <CompactAddress>[];
      for (var element in ips) {
        try {
          l.add(CompactAddress(element, announceUrl.port));
        } catch (e) {
          //
        }
      }
      return l;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent = eventType;
    return contactAnnouncer<PeerEvent>(options);
  }

  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options) {
    var list = <int>[];
    list.addAll(connectionId);

    list.addAll(
        ACTION_ANNOUNCE); // The type of Action is currently 'announce', which is represented as 1.
    list.addAll(transcationId!); // Session id
    list.addAll(infoHashBuffer);
    list.addAll(utf8.encode(options['peerId']));
    list.addAll(num2Uint64List(options['downloaded']));
    list.addAll(num2Uint64List(options['left']));
    list.addAll(num2Uint64List(options['uploaded']));
    var event = EVENTS[currentEvent];
    event ??= 0;
    list.addAll(num2Uint32List(event)); // This is the event type.
    list.addAll(num2Uint32List(0)); // This is the IP address, default is 0
    list.addAll(num2Uint32List(0)); // This is key, with the default value of 0.
    list.addAll(num2Uint32List(
        options['numwant'])); // This is num_want, with the default value of -1.
    list.addAll(num2Uint16List(options['port'])); // This is the TCP port.
    return Uint8List.fromList(list);
  }

  @override
  dynamic processResponseData(
      Uint8List data, int action, Iterable<CompactAddress> addresses) {
    if (data.length < 20) {
      // The data is incorrect
      throw Exception('announce data is wrong');
    }
    var view = ByteData.view(data.buffer);
    var event = PeerEvent(infoHash, announceUrl,
        interval: view.getUint32(8),
        incomplete: view.getUint32(16),
        complete: view.getUint32(12));
    var ips = data.sublist(20);
    var add = addresses.elementAt(0);
    var type = add.address.type;
    try {
      if (type == InternetAddressType.IPv4) {
        var list = CompactAddress.parseIPv4Addresses(ips);
        for (var c in list) {
          event.addPeer(c);
        }
      } else if (type == InternetAddressType.IPv6) {
        var list = CompactAddress.parseIPv4Addresses(ips);
        for (var c in list) {
          event.addPeer(c);
        }
      }
    } catch (e) {
      // Error tolerance
      log('Error parsing peer IP : $ips , ${ips.length}',
          name: runtimeType.toString(), error: e);
    }
    return event;
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
  void handleSocketDone() {
    dispose('Remote/Local close the socket');
  }

  @override
  void handleSocketError(e) {
    dispose(e);
  }
}
