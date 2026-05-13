import 'package:audioplayers/audioplayers.dart';

/// Plays the two short app sounds. Two players (one per sound) so a tap
/// can fire even while the achievement chime is still ringing.
///
/// Player config: low latency mode + ambient audio context, so the sound
/// respects the device silent switch and doesn't duck other apps.
class Audio {
  Audio._();
  static final Audio instance = Audio._();

  final _tap = AudioPlayer(playerId: 'tap');
  final _achievement = AudioPlayer(playerId: 'achievement');

  Future<void> init() async {
    await _prepare(_tap, 'audio/tap.wav');
    await _prepare(_achievement, 'audio/achievement.wav');
  }

  Future<void> _prepare(AudioPlayer player, String asset) async {
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player
          .setSource(AssetSource(asset))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // SoundPool can hang on some emulators / devices. Audio is a nice-to-have,
      // never a blocker — leave this player uninitialised; playback will no-op.
    }
  }

  Future<void> playTap() async {
    try {
      await _tap.stop();
      await _tap.resume();
    } catch (_) {
      // Audio failures must never break the tap UX.
    }
  }

  Future<void> playAchievement() async {
    try {
      await _achievement.stop();
      await _achievement.resume();
    } catch (_) {}
  }
}
