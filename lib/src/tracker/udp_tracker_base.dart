import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'dart:typed_data';

import '../utils.dart';

/// 第一次连接的时候，connection id是自己设置的，所有文档都提到使用该数字，说它是个magic number
const START_CONNECTION_ID_NUMER = 0x41727101980;

/// 连接起始的connection id，是个固定值 0x41727101980
const START_CONNECTION_ID = [0, 0, 4, 23, 39, 16, 25, 128];
const ACTION_CONNECT = [0, 0, 0, 0];
const ACTION_ANNOUNCE = [0, 0, 0, 1];
const ACTION_SCRAPE = [0, 0, 0, 2];
const ACTION_ERROR = [0, 0, 0, 3];

/// 套接字接收消息的超时时间，15秒
const TIME_OUT = Duration(seconds: 15);

const EVENTS = <String, int>{'completed': 1, 'started': 2, 'stopped': 3};

///
/// announce和scrapt的访问步骤完全一致，只是发送和返回数据不同，所以这里做一个mixin，
/// 具有UDP连接到host的功能，tracker和scrapter各自实现需要发送数据以及处理返回数据即可
mixin UDPTrackerBase {
  /// UDP 套接字。
  ///
  /// 基本上一次连接-响应过后就会被关闭。第二次连接再创建新的
  RawDatagramSocket _socket;

  /// 会话ID。长度为4的一组bytebuffer，随机生成的
  Uint8List _transcationId;

  /// 连接ID。在第一次发送消息到remote后，remote会返回一个connection id，第二次发送消息
  /// 需要携带该ID
  Uint8List _connectionId;

  /// 远程URL
  Uri get uri;

  /// 获取当前transcation id，如果有就返回，表示当前通信还未完结。如果没有就重新生成
  Uint8List get transcationId {
    _transcationId ??= _generateTranscationId();
    return _transcationId;
  }

  /// 将trancation id 转成数字
  int get transcationIdNum {
    return ByteData.view(transcationId.buffer).getUint32(0);
  }

  /// 生成一个随机4字节的bytebuffer
  Uint8List _generateTranscationId() {
    return randomBytes(4);
  }

  /// 与Remote通讯的第一次连接
  ///
  /// Announce 和 Scrape通讯的时候，都必须要走这第一步，是固定的。
  ///
  /// 参数completer是一个`Completer`实例。用于截获发生的异常，并通过completeError截获
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

  ///
  /// 退出整个通信并让completer获取到异常
  void _returnError(Completer completer, dynamic error) {
    _clean();
    completer.completeError(error);
  }

  /// 和Remote通信的入口函数。返回一个Future
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

  /// 处理一次通信最终从remote获得的数据.
  /// 
  dynamic processResponseData(Uint8List data, int action);

  ///
  /// 与announce和scrape通信的时候，在第一次连接成功后，第二次发送的数据是不同的。
  /// 这个方法就是让子类分别实现annouce和scrape不同的发送数据
  Uint8List generateSecondTouchMessage(Uint8List connectionId);

  ///
  /// 第一次连接成功后，发送第二次信息
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

  /// 处理从套接字处读出到的信息。
  ///
  /// 该方法并不会直接去处理Remote返回的最终消息，而且固定了整个通信流程。
  /// 该方法会去处理在第一次发送信息后收到消息，然后到接收到第二次消息的整个过程
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

  /// 关闭套接字
  void _clean() {
    _socket?.close();
    _socket = null;
  }

  /// 发送数据包到指定的ip地址
  Future _sendMessage(Uint8List message, String host, int port) async {
    var ips = await InternetAddress.lookup(host);
    ips.forEach((ip) {
      // print('send $message to $ip : ${_uri.port}');
      _socket?.send(message, ip, port);
    });
  }
}
