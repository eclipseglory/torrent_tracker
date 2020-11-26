import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'dart:typed_data';

mixin HttpTrackerBase {
  HttpClient _httpClient;

  Map<String, dynamic> generateQueryParameters();

  Uri get url;

  /// 创建访问URL。
  ///
  /// 其中子类必须实现url属性以及generateQueryParameters方法，才能正确发起访问
  String _createAccessURL() {
    var url = this.url;
    if (url == null) {
      throw Exception('URL can not be empty');
    }

    var parameters = generateQueryParameters();
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
    var str = url.toString();
    if (str.contains('&')) {
      print('here');
    }
    str = '${url.origin}${url.path}?';
    if (!str.contains('?')) str += '?';
    str += _queryStr;
    return str;
  }

  void clean() {
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  ///
  /// Http get访问。返回Future，如果访问出现问题，比如响应码不是200，超时，数据接收出问题，URL
  /// 解析错误等，都会被Future的catchError截获。
  ///
  Future httpGet() async {
    var completer = Completer();
    _httpClient ??= HttpClient();
    var url;
    try {
      url = _createAccessURL();
    } catch (e) {
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
          var result;
          try {
            result = processResponseData(Uint8List.fromList(data));
            completer.complete(result);
            return;
          } catch (e) {
            completer.completeError(e);
          }
        }, onError: (e) {
          completer.completeError(e); // 截获获取响应时候的错误
        });
      } else {
        log('响应码表示有问题',
            time: DateTime.now(),
            error: Exception('Response Code : ${response.statusCode}'),
            name: runtimeType.toString());
        completer.completeError(
            'Access ${this.url.origin}${this.url.path} error , status code: ${response.statusCode}');
      }
    } catch (e) {
      log('访问出错', time: DateTime.now(), error: e, name: runtimeType.toString());
      completer.completeError(e);
    }
    return completer.future;
  }

  dynamic processResponseData(Uint8List data);
}
