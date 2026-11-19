import 'package:flutter_test/flutter_test.dart';

import 'package:boardpad/widgets/home/wifi_widget.dart';

void main() {
  test('133차 와이파이 QR 글: 보통·비밀번호 없음·숨긴 네트워크·특수 문자', () {
    expect(wifiQrData(ssid: 'GoDori_5G', password: 'board1234'), 'WIFI:T:WPA;S:GoDori_5G;P:board1234;;');
    expect(wifiQrData(ssid: 'Free', password: ''), 'WIFI:T:nopass;S:Free;;');
    expect(wifiQrData(ssid: 'Cafe', password: 'x', security: 'nopass'), 'WIFI:T:nopass;S:Cafe;;');
    expect(wifiQrData(ssid: 'Hide', password: 'pw', hidden: true), 'WIFI:T:WPA;S:Hide;P:pw;H:true;;');
    expect(wifiQrData(ssid: 'a;b', password: r'p:w"\,'), r'WIFI:T:WPA;S:a\;b;P:p\:w\"\\\,;;');
  });
}
