import 'utils.dart';

import 'tracker/tracker_base.dart';

abstract class ScraperGenerator {
  Scrape createScrape(Uri announceUrl);

  factory ScraperGenerator.base() {
    return BaseScraperGenerator();
  }
}

class BaseScraperGenerator implements ScraperGenerator {
  @override
  Scrape createScrape(Uri announceUrl) {
    if (announceUrl == null) return null;
    if (announceUrl.isScheme('https') || announceUrl.isScheme('http')) {
      // 将announce url转成scrape url，如果announce不具备scrape url条件，将返回null
      var url = transformToScrapeUrl(announceUrl.toString());
      if (url == null) return null;
      return HttpScrape(Uri.parse(url));
    }
    if (announceUrl.isScheme('udp')) return UDPScrape(announceUrl);
    return null;
  }
}
