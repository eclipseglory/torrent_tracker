## About

Dart implementation of a BitTorrent Http/Https and UDP tracker/scrape client

## Support
- [BEP 0003 HTTP/HTTPS Tracker/Scrape](https://www.bittorrent.org/beps/bep_0003.html)
- [BEP 0015 UDP Tracker/Scrape](https://www.bittorrent.org/beps/bep_0015.html)
- [BEP 0007 IPv6 Tracker Extension](https://www.bittorrent.org/beps/bep_0007.html)
## How to use it

### Tracker
To create the `TorrentAnnounceTracker` instance, the parameter `AnnounceOptionProvider` should be provided.
Howerver, there is not any implements , user have to implement it manually:
```dart
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
      'compact': compact,// it should be 1
      'numwant': numwant, // max is 50
      'peerId': peerId,
      'port': port
    });
  }
}
```
When we have the `AnnounceOptionsProvider` instance, we can create a `TorrentAnnounceTracker` like this:
```dart
    var torrentTracker = TorrentAnnounceTracker(SimpleProvider(....));
```
`TorrentAnnounceTracker` have some methods to run `started`,`stopped`,`completed` announce event:
```dart
    torrentTracker.runTracker(url,infohash,event:'started');
```
We can add some listener on the torrentTracker to get the announce result:
```dart
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
```


### Scrape
Create a `TorrentScrapeTracker` instance:
```dart
var scrapeTracker = TorrentScrapeTracker();
```
Then add the scrape url (same with the announce tracker url, TorrentScrapeTracker will transform it) and infohash buffer to create a `Scrape`:
```dart
scrapeTracker.addScrapes(torrent.announces, torrent.infoHashBuffer);
```
**NOTE**: The `Scrape` can add more than one infoHashbuffer , because it can "scrape" multiple torrent informations at one time, so if user invoke `addScrapes` or `addScrape` with same url but different infohashbuffer , it will return the same `Scrape` instance.

To get the scrape result:

```dart
scrapeTracker.scrape(torrent.infoHashBuffer).listen((event) {
    print(event);
});
```
The method `scrape` need a infoHashbuffer as the parameter and return a `Stream` , user can listen the `Stream` event to get the result.