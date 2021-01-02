import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

///
/// Because access announce or scrape url , the access workflow is the same , but different url
/// with diffrent query string. So this class implement the http access announce main processes,
/// such as connect , catch error , close client and so on.
///
/// The classes which [with] this mixin , need to implement ```generateQueryParameters``` method, ```url``` property
/// ```processResponseData``` method.
/// - ```generateQueryParameters``` return the query parameters map , this class will make them to be the query string
/// - ```url``` the announce or scrape url
/// - ```processResponseData``` deal with the response byte buffer , and return the useful informations from announce.
///
///
/// Invoke ```httpGet``` method to start access remote , see HttpTracker:
///
/// ```dart
///    @override
///    Future announce(String event) {
///      _currentEvent = event;
///      return httpGet();
///    }
///
/// ```
///
/// It record the event type and invoke httpGet directly to access remote. of course , it has implemented the abstract method and
/// property of this mixin.
///
///
mixin HttpTrackerBase {
  HttpClient _httpClient;

  /// Return a map with query params.
  /// [options] is a map , it help to generate paramter
  ///
  /// *NOTE*
  ///
  /// The param map's key is the query pair'key , it allow the duplicated key:
  ///
  /// `http://some.com?key=value1&key=value2`
  ///
  /// so , the param map's value is not `String` type but `dynamic`, because it can be a `List`.
  /// If the value is `List` , the query string will be generated with duplicate key :
  /// ```dart
  ///   var map = <String,List>{};
  ///   var list = ['Sam','Bob'];
  ///   map['name'] = list;
  ///   return map;
  /// ```
  /// Then access url with the query string will be : `http://remoteurl?name=Sam&name=Bob`
  Map<String, dynamic> generateQueryParameters(Map<String, dynamic> options);

  /// Return the remote Url
  Uri get url;

  /// 创建访问URL。
  ///
  /// 其中子类必须实现url属性以及generateQueryParameters方法，才能正确发起访问
  String _createAccessURL(Map<String, dynamic> options) {
    var url = this.url;
    if (url == null) {
      throw Exception('URL can not be empty');
    }

    var parameters = generateQueryParameters(options);
    if (parameters == null || parameters.isEmpty) {
      throw Exception('Query params can not be empty');
    }

    var _queryStr = parameters.keys.fold('', (previousValue, key) {
      var values = parameters[key];
      if (values is String) {
        previousValue += '&$key=$values';
        return previousValue;
      }
      if (values is List) {
        values.forEach((value) => previousValue += '&$key=$value');
        return previousValue;
      }
    });
    // if (_queryStr.isNotEmpty) _queryStr = _queryStr.substring(1); scrape
    var str = _rawUrl;
    str = '${url.origin}${url.path}?';
    if (!str.contains('?')) str += '?';
    str += _queryStr;
    return str;
  }

  String get _rawUrl {
    return '${url.origin}${url.path}';
  }

  ///
  /// close the http client
  void close() {
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  ///
  /// Http get访问。返回Future，如果访问出现问题，比如响应码不是200，超时，数据接收出问题，URL
  /// 解析错误等，都会被Future的catchError截获。
  ///
  Future<T> httpGet<T>(Map<String, dynamic> options) async {
    var completer = Completer<T>();
    _httpClient ??= HttpClient();
    var url;
    try {
      url = _createAccessURL(options);
    } catch (e) {
      close();
      completer.completeError(e);
      return completer.future;
    }
    try {
      var uri = Uri.parse(url);
      var request = await _httpClient.getUrl(uri);
      var response = await request.close();
      if (response.statusCode == 200) {
        var data = <int>[];
        response.listen((bytes) {
          data.addAll(bytes);
        }, onDone: () {
          if (completer.isCompleted) return;
          try {
            var result = processResponseData(Uint8List.fromList(data));
            completer.complete(result);
          } catch (e) {
            close();
            completer.completeError(e);
          }
        }, onError: (e) {
          close();
          completer.completeError(e); // 截获获取响应时候的错误
        });
      } else {
        close();
        completer.completeError('status code: ${response.statusCode}');
      }
    } catch (e) {
      close();
      completer.completeError(e);
    }
    return completer.future;
  }

  /// Process the remote response byte buffer and return the useful informations they need.
  dynamic processResponseData(Uint8List data);
}
