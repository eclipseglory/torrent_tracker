import 'utils.dart';

import 'tracker/tracker_base.dart';

abstract class ScraperGenerator {
  Scrape? createScrape(Uri announceUrl);

  factory ScraperGenerator.base() {
    return BaseScraperGenerator();
  }
}

class BaseScraperGenerator implements ScraperGenerator {
  @override
  Scrape? createScrape(Uri announceUrl) {
    if (announceUrl.isScheme('https') || announceUrl.isScheme('http')) {
      // Convert the announce URL to a scrape URL.
      // If the announce does not have the necessary conditions for a scrape URL
      //, it will return null.
      var url = transformToScrapeUrl(announceUrl.toString());
      if (url == null) return null;
      return HttpScrape(Uri.parse(url));
    }
    if (announceUrl.isScheme('udp')) return UDPScrape(announceUrl);
    return null;
  }
}
