import 'dart:typed_data';

String? transformToScrapeUrl(String url) {
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
    return ('${url.substring(0, startIndex)}scrape');
  } else {
    var next = url.substring(i, i + 1);
    if (next == '?' || next == '/' || next == '\\') {
      return ('${url.substring(0, startIndex)}scrape${url.substring(i)}');
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

dynamic getPeerIPv4(ByteData byteView, [int offset = 0]) {
  var a = byteView.getUint8(offset);
  var b = byteView.getUint8(offset + 1);
  var c = byteView.getUint8(offset + 2);
  var d = byteView.getUint8(offset + 3);
  var port = byteView.getUint16(offset + 4, Endian.big);
  return Uri(host: '$a.$b.$c.$d', port: port);
}
