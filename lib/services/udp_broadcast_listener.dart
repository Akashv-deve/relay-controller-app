import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

// --- THE PASSIVE UDP LISTENER ENGINE ---
class UdpBroadcastListener {
  RawDatagramSocket? _udpSocket;

  Future<void> startListening(Function(String name, String ip) onHubFound) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8888);
      _udpSocket!.broadcastEnabled = true;

      debugPrint('🎧 Listening for RP2350B Broadcasts on port 8888...');

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram = _udpSocket!.receive();
          
          if (datagram != null) {
            String message = utf8.decode(datagram.data);
            debugPrint('📡 Broadcast intercepted: $message');

            try {
              final data = json.decode(message);
              if (data.containsKey('ip') && data.containsKey('name')) {
                onHubFound(data['name'], 'http://${data['ip']}');
              }
           } catch (e) {
  debugPrint('Failed to parse broadcast JSON: $e');
}
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to bind UDP socket: $e');
    }
  }

  void stopListening() {
    _udpSocket?.close();
    debugPrint('🛑 Stopped listening for broadcasts.');
  }
}