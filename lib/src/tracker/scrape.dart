///
/// Torrent Scrape class.
///
/// announce allow client to access them to get some simple informations ,
/// such as downloaded,completed,incompleted , this class provide some interface
/// to access the announce with scrape method.
abstract class Scrape {
  final Set _infoHashList = {};

  /// Scrape Url
  Uri scrapeUrl;

  /// Scrape Id
  final String id;

  Scrape(this.id, this.scrapeUrl);

  ///
  /// Call this method , client will access the scrape url to get the scrape informations.
  /// It return a Future , if success , it will return the informations include downloaded,
  /// completed , incompleted and other unofficial informations.
  Future scrape();

  ///
  /// Torrent file infomations hash string set.
  ///
  /// the announce scrape allow client to get mutiple torrent file informations , this property
  ///  store the torrent files info hash string.
  ///
  Set get infoHashSet {
    return _infoHashList;
  }

  /// Add a torrent file info hash string. if it existed , this method will return false, or return true
  bool addInfoHash(String infoHash) {
    return _infoHashList.add(infoHash);
  }

  /// Remove a torrent file info hash string. if it inst existed, will return false, or return true;
  bool removeInfoHash(String infoHash) {
    return _infoHashList.remove(infoHash);
  }
}
