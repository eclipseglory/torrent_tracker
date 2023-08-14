import 'dart:typed_data';

import '../dtorrent_tracker.dart';

abstract class TrackerGenerator {
  Tracker? createTracker(
      Uri announce, Uint8List infoHashBuffer, AnnounceOptionsProvider provider);

  factory TrackerGenerator.base() {
    return BaseTrackerGenerator();
  }
}

class BaseTrackerGenerator implements TrackerGenerator {
  @override
  Tracker? createTracker(Uri announce, Uint8List infoHashBuffer,
      AnnounceOptionsProvider provider) {
    if (announce.isScheme('http') || announce.isScheme('https')) {
      return HttpTracker(announce, infoHashBuffer, provider: provider);
    }
    if (announce.isScheme('udp')) {
      return UDPTracker(announce, infoHashBuffer, provider: provider);
    }
    return null;
  }
}
