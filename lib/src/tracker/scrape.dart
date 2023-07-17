import 'dart:typed_data';

///
/// Torrent Scrape class.
///
/// announce allow client to access them to get some simple informations ,
/// such as downloaded,completed,incompleted , this class provide some interface
/// to access the announce with scrape method.
abstract class Scrape {
  final Set<Uint8List> _infoHashList = {};

  /// Scrape Url
  Uri scrapeUrl;

  /// Scrape Tracker Id , usually use scrape url
  final String id;

  int maxRetryTime;

  Scrape(this.id, this.scrapeUrl, [this.maxRetryTime = 3]);

  ///
  /// Call this method , client will access the scrape url to get the scrape informations.
  /// It return a Future , if success , it will return the informations include downloaded,
  /// completed , incompleted and other unofficial informations.
  Future scrape(Map<String, dynamic> options);

  ///
  /// Torrent file infomations hash bytebuffer set.
  ///
  /// the announce scrape allow client to get mutiple torrent file informations , this property
  ///  store the torrent files info hash bytebuffer.
  ///
  Set<Uint8List> get infoHashSet {
    return _infoHashList;
  }

  /// Add a torrent file info hash bytebuffer. if it existed , this method will return false, or return true
  bool addInfoHash(Uint8List infoHashBuffer) {
    return _infoHashList.add(infoHashBuffer);
  }

  /// Remove a torrent file info hash bytebuffer. if it inst existed, will return false, or return true;
  bool removeInfoHash(Uint8List infoHashBuffer) {
    return _infoHashList.remove(infoHashBuffer);
  }

  @override
  bool operator ==(other) {
    if (other is Scrape) return other.id == id;
    return false;
  }

  @override
  int get hashCode => id.hashCode;
}
