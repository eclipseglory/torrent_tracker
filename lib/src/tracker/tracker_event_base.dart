/// The tracker base event.
class TrackerEventBase {
  final Map _others = {};

  Map get otherInfomationsMap {
    return _others;
  }

  void setInfo(key, value) {
    _others[key] = value;
  }

  dynamic removeInfo(key) {
    return _others.remove(key);
  }
}
