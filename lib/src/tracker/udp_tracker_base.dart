import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'dart:typed_data';

import '../utils.dart';

const START_CONNECTION_ID_NUMER = 0x41727101980;

/// 连接起始的connection id，是个固定值 0x41727101980
const START_CONNECTION_ID = [0, 0, 4, 23, 39, 16, 25, 128];
const ACTION_CONNECT = [0, 0, 0, 0];
const ACTION_ANNOUNCE = [0, 0, 0, 1];
const ACTION_SCRAPE = [0, 0, 0, 2];
const ACTION_ERROR = [0, 0, 0, 3];
const TIME_OUT = Duration(seconds: 15);

const EVENTS = <String, int>{'completed': 1, 'started': 2, 'stopped': 3};

///
/// announce和scrapt的访问步骤完全一致，只是发送和返回数据不同，所以这里做一个mixin，
/// 具有UDP连接到host的功能，tracker和scrapter各自实现需要发送数据以及处理返回数据即可
mixin UDPTrackerBase {
  RawDatagramSocket _socket;
  var _transcationId;
  Uint8List _connectionId;

  Uint8List get transcationId {
    _transcationId ??= _generateTranscationId();
    return _transcationId;
  }

  int get transcationIdNum {
    return ByteData.view(transcationId.buffer).getUint32(0);
  }

  Uint8List _generateTranscationId() {
    return randomBytes(4);
  }

  void _connect(Completer completer) {
    var uri = this.uri;
    if (uri == null) _returnError(completer, '目标地址Uri不能为空');
    var list = <int>[];
    list.addAll(START_CONNECTION_ID); //这是个magic id
    list.addAll(ACTION_CONNECT);
    list.addAll(transcationId);
    var messageBytes = Uint8List.fromList(list);
    _sendMessage(messageBytes, uri.host, uri.port).catchError((e) {
      _returnError(completer, e);
    });
  }

  void _returnError(Completer completer, dynamic error) {
    _clean();
    completer.completeError(error);
  }

  Future contactAnnouncer() async {
    var completer = Completer();
    _socket?.close();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    var eventStream = _socket.timeout(TIME_OUT, onTimeout: (e) {
      _clean();
      log('连接 $uri 超时', error: '超时', name: runtimeType.toString());
      if (!completer.isCompleted) completer.completeError('连接超时');
    });

    eventStream.listen((event) {
      if (event == RawSocketEvent.read) {
        var datagram = _socket.receive();
        if (datagram == null || datagram.data.length < 8) {
          _clean();
          completer.completeError('Transaction ID from tracker is wrong');
          return;
        }
        _processAnnounceResponseData(datagram.data, completer);
      }
    }, onError: (e) {
      _clean();
      completer.completeError(e);
    });

    // 第一步，连接对方
    try {
      _connect(completer);
    } catch (e) {
      _clean();
      completer.completeError(e);
      return;
    }
    return completer.future;
  }

  dynamic processResponseData(Uint8List data, int action);

  Uint8List generateSecondTouchMessage(Uint8List connectionId);

  void _announce(Completer completer, Uint8List connectionId) {
    var message = generateSecondTouchMessage(connectionId);
    var uri = this.uri;
    if (uri == null) _returnError(completer, '目标地址Uri不能为空');
    if (message == null || message.isEmpty) {
      _returnError(completer, '发送数据不能为空');
    } else {
      _sendMessage(message, uri.host, uri.port).catchError((e) {
        _returnError(completer, e);
      });
    }
  }

  Uri get uri;

  void _processAnnounceResponseData(Uint8List data, Completer completer) {
    var view = ByteData.view(data.buffer);
    var tid = view.getUint32(4);
    if (tid == transcationIdNum) {
      var action = view.getUint32(0);
      // 表明连接成功，可以进行announce
      if (action == 0) {
        // print('$announceUrl connect success , ready to announce');
        try {
          _connectionId = data.sublist(8, 16); // 返回信息的第8-16位是下次连接的connection id
          _announce(completer, _connectionId); // 继续，不要停
        } catch (e) {
          _clean();
          log('在发送给announcer消息的时候出错', error: e, name: runtimeType.toString());
          completer.completeError(
              'error happens during announce , from ${uri.host}');
        }
        return;
      }
      // 发生错误
      if (action == 3) {
        _clean();
        var errorMsg = String.fromCharCodes(data.sublist(8));
        log('获得announcer的错误返回信息',
            error: errorMsg, name: runtimeType.toString());
        completer.completeError(errorMsg);
        return;
      }
      // announce获得返回结果
      _clean(); // Announce获得结果后就关闭socket不再监听。
      // print('$announceUrl announce success , ready to read data');
      // print(data);
      var result;
      try {
        result = processResponseData(data, action);
      } catch (e) {
        completer.completeError('处理数据时发生错误 $e');
        return;
      }
      completer.complete(result);
      log('Action : $action ,成功获得announcer数据 : $result',
          name: runtimeType.toString());
      return;
    }
  }

  void _clean() {
    _socket?.close();
    _socket = null;
  }

  Future _sendMessage(Uint8List message, String host, int port) async {
    var ips = await InternetAddress.lookup(host);
    ips.forEach((ip) {
      // print('send $message to $ip : ${_uri.port}');
      _socket?.send(message, ip, port);
    });
  }
}
