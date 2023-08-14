import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:dtorrent_common/dtorrent_common.dart';

/// During the first connection, the connection ID is set by yourself, and all
/// documents mention using this number, referring to it as a "magic number."
const START_CONNECTION_ID_NUMER = 0x41727101980;

/// The starting connection ID is a fixed value: 0x41727101980.
const START_CONNECTION_ID = [0, 0, 4, 23, 39, 16, 25, 128];
const ACTION_CONNECT = [0, 0, 0, 0];
const ACTION_ANNOUNCE = [0, 0, 0, 1];
const ACTION_SCRAPE = [0, 0, 0, 2];
const ACTION_ERROR = [0, 0, 0, 3];

/// The socket's receive message timeout is set to 15 seconds.
const TIME_OUT = Duration(seconds: 15);

const EVENTS = <String, int>{'completed': 1, 'started': 2, 'stopped': 3};

///
/// The access steps for announce and scrape are exactly the same;
/// only the sent and returned data are different. Therefore, we create a mixin
/// here that contains the functionality of establishing a UDP connection to the
/// host. The tracker and scraper will each implement the logic for sending data
/// and processing returned data accordingly.
///
mixin UDPTrackerBase {
  /// UDP socket
  ///
  /// Basically, once the connection is made, it is closed after the response.
  /// The second connection creates a new one
  RawDatagramSocket? _socket;

  /// Session ID. A group of 4 bytes represented as a byte buffer, randomly generated.
  List<int>? _transcationId;

  /// Connection ID. After sending the first message to the remote, the remote
  ///  will return a connection ID, which needs to be carried when sending the
  ///  second message.
  Uint8List? _connectionId;

  /// Remote URL
  // Uri get uri;

  Future<List<CompactAddress>?> get addresses;

  bool _closed = false;

  bool get isClosed => _closed;

  /// Obtain the current transcation ID, and return it if there is, indicating that the current communication has not ended. If not, regenerate
  List<int>? get transcationId {
    _transcationId ??= _generateTranscationId();
    return _transcationId;
  }

  /// Convert the trancation ID to a number
  int get transcationIdNum {
    return ByteData.view(Uint8List.fromList(transcationId!).buffer)
        .getUint32(0);
  }

  /// Generate a random 4-byte buffer
  List<int> _generateTranscationId() {
    return randomBytes(4);
  }

  int maxConnectRetryTimes = 3;

  ///
  /// The first connection to the Remote communication
  /// When announcing and scrape communicate, this first step must be taken, which is fixed.
  /// The parameter completer is an instance of 'Completer'. Used to intercept exceptions that occur and intercept them through completeError
  ///
  void _connect(
      Map options, List<CompactAddress> address, Completer completer) async {
    if (isClosed) {
      if (!completer.isCompleted) completer.completeError('Tracker closed');
      return;
    }
    var list = <int>[];
    list.addAll(START_CONNECTION_ID); //This is a magic ID
    list.addAll(ACTION_CONNECT);
    list.addAll(transcationId!);
    var messageBytes = Uint8List.fromList(list);
    try {
      _sendMessage(messageBytes, address);
      return;
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
      close();
    }
  }

  /// An entry function that communicates with Remote. Returns a Future
  Future<T?> contactAnnouncer<T>(Map options) async {
    if (isClosed) return null;
    var completer = Completer<T>();
    var adds = await addresses;
    if (adds == null || adds.isEmpty) {
      close();
      if (!completer.isCompleted) {
        completer.completeError('InternetAddress cant be null');
      }
      return completer.future;
    }
    _socket?.close();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket?.listen((event) async {
      if (event == RawSocketEvent.read) {
        var datagram = _socket?.receive();
        if (datagram == null || datagram.data.length < 8) {
          close();
          completer.completeError('Wrong datas');
          return;
        }
        _processAnnounceResponseData(datagram.data, options, adds, completer);
      }
    }, onError: (e) async {
      close();
      handleSocketError(e);
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      handleSocketDone();
      if (!completer.isCompleted) completer.completeError('Socket closed');
    });

    // Step 1: Connect to the other party
    _connect(options, adds, completer);
    return completer.future;
  }

  void handleSocketDone();

  void handleSocketError(e);

  /// Process the data obtained from the remote after one communication.
  ///
  dynamic processResponseData(
      Uint8List data, int action, Iterable<CompactAddress> addresses);

  ///
  /// When communicating with announce and scrape, the data sent in the second
  /// communication is different after the first successful connection.
  /// This method is designed for subclasses to implement different data sending
  /// logic for announce and scrape
  ///
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options);

  ///
  /// After the first connection is successful, send the second message
  Future<void> _announce(Uint8List connectionId, Map options,
      List<CompactAddress> addresses) async {
    var message = generateSecondTouchMessage(connectionId, options);
    if (message.isEmpty) {
      throw 'The sent data cannot be empty';
    } else {
      _sendMessage(message, addresses);
    }
  }

  /// Process the information read from the socket.
  ///
  /// This method does not directly handle the final message returned from the Remote, but it fixes the entire communication flow.
  /// This method processes the entire process from sending the first message and receiving the response to receiving the second message.
  void _processAnnounceResponseData(Uint8List data, Map options,
      List<CompactAddress> address, Completer completer) async {
    if (isClosed) {
      if (!completer.isCompleted) completer.completeError('Tracker Closed');
      return;
    }
    var view = ByteData.view(data.buffer);
    var tid = view.getUint32(4);
    if (tid == transcationIdNum) {
      var action = view.getUint32(0);
      // Indicates a successful connection, and announce can be performed.
      if (action == 0) {
        _connectionId = data.sublist(8,
            16); //The 8th to 16th bits of the returned information are the connection ID for the next connection
        await _announce(
            _connectionId!, options, address); // Continue, don't stop
        return;
      }
      // An error occurred.
      if (action == 3) {
        var errorMsg = 'Unknown error';
        try {
          errorMsg = String.fromCharCodes(data.sublist(8));
        } catch (e) {
          //
        }
        if (!completer.isCompleted) {
          completer.completeError(errorMsg);
        }
        close();
        return;
      }
      // Announce receives the returned result
      try {
        var result = processResponseData(data, action, address);
        completer.complete(result);
      } catch (e) {
        completer.completeError('Response Announce Result Data error');
      }
      close();
    } else {
      if (!completer.isCompleted) {
        completer.completeError('Transacation ID incorrect');
      }
      await close();
    }
  }

  /// Close the connection and clear settings
  Future<void> close() {
    _closed = true;
    _socket?.close();
    _socket = null;
    return Future.wait([]);
  }

  /// Send a data packet to a specific IP address
  void _sendMessage(Uint8List message, List<CompactAddress> addresses) {
    if (isClosed) return;
    var success = false;
    for (var element in addresses) {
      var bytes = _socket?.send(message, element.address, element.port);
      if (bytes != 0) success = true;
    }
    if (!success) {
      Timer.run(() => _sendMessage(message, addresses));
    }
  }
}
