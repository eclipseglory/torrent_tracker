import 'package:dartorrent_common/dartorrent_common.dart';

import 'tracker_event_base.dart';

///
/// This class recorded the response from remote when tracker access announce successfully
class PeerEvent extends TrackerEventBase {
  /// Event type :
  /// - [START]
  /// - [COMPLETE]
  /// - [STOPPED]
  String eventType;

  /// Server host url
  final Uri serverHost;

  /// Torrent info hash string
  final String infoHash;

  /// number of peers with the entire file, i.e. seeders
  int complete;

  /// total number of times the tracker has registered a completion
  int downloaded;

  /// number of non-seeder peers, aka "leechers"
  int incomplete;

  /// Interval in seconds that the client should wait between sending regular requests to the tracker
  int interval;

  /// Minimum announce interval. If present clients must not reannounce more frequently than this.
  int minInterval;

  /// Similar to failure reason, but the response still gets processed normally. The warning message is shown just like an error.
  String warning;

  /// peer uri set
  Set<CompactAddress> peers = <CompactAddress>{};

  PeerEvent(this.infoHash, this.serverHost,
      {this.complete,
      this.incomplete,
      this.interval,
      this.minInterval,
      this.warning});

  /// Add a peer uri
  bool addPeer(CompactAddress peer) {
    return peers.add(peer);
  }

  /// Remove a peer uri
  bool removePeer(CompactAddress peer) {
    return peers.remove(peer);
  }

  @override
  String toString() {
    var str = 'Torrent($infoHash) [$serverHost]:\n';
    str +=
        'complete:$complete, incomplete:$incomplete, downloaded:$downloaded, interval:$interval, minInterval:$minInterval\n';
    str += warning == null ? '' : 'WARNING:$warning \n';
    if (peers.isNotEmpty) {
      str += 'Peers List(${peers.length}): \n';
      peers.forEach((peer) {
        str += '$peer \n';
      });
    } else {
      str += 'Peers List is empty \n';
    }
    if (otherInfomationsMap.isNotEmpty) {
      str += '$otherInfomationsMap';
    }
    return str;
  }
}
