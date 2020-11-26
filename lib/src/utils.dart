import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Uint8List randomBytes(count) {
  var random = math.Random();
  var bytes = Uint8List(count);
  for (var i = 0; i < count; i++) {
    bytes[i] = random.nextInt(254);
  }
  return bytes;
}

String transformToScrapeUrl(String url) {
  var lastIndex = url.lastIndexOf('/');
  if (lastIndex == -1) {
    lastIndex = url.lastIndexOf('\\');
    if (lastIndex == -1) return null;
  }

  if (lastIndex == url.length - 1) {
    url = url.substring(0, url.length - 1);
    return transformToScrapeUrl(url);
  }
  var startIndex = url.indexOf('announce', lastIndex);
  if (startIndex == -1) return null;
  var i = startIndex + 'announce'.length;
  if (i >= url.length) {
    return (url.substring(0, startIndex) + 'scrape');
  } else {
    var next = url.substring(i, i + 1);
    if (next == '?' || next == '/' || next == '\\') {
      return (url.substring(0, startIndex) + 'scrape' + url.substring(i));
    }
  }
  return null;
}

Uint8List num2Uint16List(n) {
  var buffer = Uint16List(1).buffer;
  ByteData.view(buffer).setUint16(0, n);
  return buffer.asUint8List();
}

Uint8List num2Uint32List(n) {
  var buffer = Uint32List(1).buffer;
  ByteData.view(buffer).setUint32(0, n);
  return buffer.asUint8List();
}

Uint8List num2Uint64List(n) {
  var buffer = Uint64List(1).buffer;
  ByteData.view(buffer).setUint64(0, n);
  return buffer.asUint8List();
}

Future udpSendMessageToHost(
    RawDatagramSocket socket, String host, int port, Uint8List message) async {
  var ipList = await InternetAddress.lookup(host);
  if (ipList == null || ipList.isEmpty) return;
  return ipList.map((ip) => socket.send(message, ip, port));
}

dynamic getPeerIPv4(ByteData byteView, [int offset = 0]) {
  var a = byteView.getUint8(offset);
  var b = byteView.getUint8(offset + 1);
  var c = byteView.getUint8(offset + 2);
  var d = byteView.getUint8(offset + 3);
  var port = byteView.getUint16(offset + 4);
  return {'ip': '$a.$b.$c.$d', 'port': port};
  // switch (bytes.length) {
  //   case 6:
  //     return buf[0] +
  //         "." +
  //         buf[1] +
  //         "." +
  //         buf[2] +
  //         "." +
  //         buf[3] +
  //         ":" +
  //         buf.readUInt16BE(4);
  //     break;
  //   case 18:
  //     var hexGroups = [];
  //     for (var i = 0; i < 8; i++) {
  //       hexGroups.push(buf.readUInt16BE(i * 2).toString(16));
  //     }
  //     var host = ipaddr.parse(hexGroups.join(":")).toString();
  //     return "[" + host + "]:" + buf.readUInt16BE(16);
  //   default:
  //     throw new Error(
  //         "Invalid Compact IP/PORT, It should contain 6 or 18 bytes");
  // }
}

List getPeerIPv4List(Uint8List bytes) {
  var list = [];
  if (bytes == null || bytes.isEmpty) return list;
  if (bytes.length % 6 != 0) {
    throw Exception('buf length isn\'t multiple of compact IP/PORTs (6 bytes)');
  }
  var view = ByteData.view(bytes.buffer);

  for (var i = 0; i < bytes.length; i += 6) {
    list.add(getPeerIPv4(view, i));
  }
  return list;
}
