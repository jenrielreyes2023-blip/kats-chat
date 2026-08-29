import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class ChatSounds {
  static AudioPlayer? _sentPlayer;
  static AudioPlayer? _receivedPlayer;

  static Future<void> _init() async {
    if (_sentPlayer != null) return;
    try {
      _sentPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      _receivedPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('ChatSounds init error: $e');
    }
  }

  /// Plays crisp iPhone-style outgoing swoosh/pop sound when message is sent
  static Future<void> playSent() async {
    try {
      await _init();
      await _sentPlayer?.stop();
      await _sentPlayer?.play(AssetSource('sounds/message_sent.wav'), mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('Error playing sent sound: $e');
    }
  }

  /// Plays crisp iPhone-style incoming chime/pop sound when message is received
  static Future<void> playReceived() async {
    try {
      await _init();
      await _receivedPlayer?.stop();
      await _receivedPlayer?.play(AssetSource('sounds/message_received.wav'), mode: PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('Error playing received sound: $e');
    }
  }
}
