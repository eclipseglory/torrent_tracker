abstract class Scrape {
  final Set _infoHashList = {};

  Uri scrapeUrl;

  final String id;

  Scrape(this.id, this.scrapeUrl);

  Future scrape();

  Set get infoHashSet {
    return _infoHashList;
  }

  bool addInfoHash(String infoHash) {
    return _infoHashList.add(infoHash);
  }

  bool removeInfoHash(String infoHash) {
    return _infoHashList.remove(infoHash);
  }
}
