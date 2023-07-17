import 'tracker_event_base.dart';

///
/// When tracker scrape success, it will send [ScrapeEvent] via Stream.
///
/// [ScrapeEvent] contains some scrape response informations, such as :
/// complete,incomplete,downloaded..
///
/// See [Tracker 'scrape' convertion](https://wiki.theory.org/BitTorrentSpecification#Tracker_.27scrape.27_Convention)
class ScrapeEvent extends TrackerEventBase {
  /// Scrape server address .
  ///
  /// NOTE: we can scrape mutiple files from same host
  final Uri serverHost;

  ///  A dictionary containing one key/value pair for each torrent for which there are stats.
  final Map files = <String, ScrapeResult>{};

  /// A dictionary containing miscellaneous flags. The value of the flags key is another nested dictionary
  final Map flags = {};

  ScrapeEvent(this.serverHost);

  void addFile(String infoHash, ScrapeResult result) {
    files[infoHash] = result;
  }

  ScrapeResult removeFile(String infoHash) {
    return files.remove(infoHash);
  }

  @override
  String toString() {
    var title = '${serverHost.toString()} Scrape Result: \n';
    files.forEach((key, value) => title += '${value.toString()}\n');
    return title;
  }
}

///
/// For single file scrape result
class ScrapeResult extends TrackerEventBase {
  /// number of peers with the entire file, i.e. seeders
  int? complete;

  /// number of non-seeder peers, aka "leechers"
  int? incomplete;

  /// total number of times the tracker has registered a completion
  int? downloaded;

  /// Torrent info hash string
  final String infoHash;

  /// the torrent's internal name, as specified by the "name" file in the info section of the .torrent file
  String? name;

  ScrapeResult(this.infoHash,
      {this.complete, this.incomplete, this.downloaded, this.name});

  @override
  String toString() {
    return 'File($infoHash) : complete:$complete, incomplete:$incomplete, downloaded:$downloaded, name:$name' +
        (otherInfomationsMap.isEmpty
            ? ''
            : '\n${otherInfomationsMap.toString()}');
  }
}
