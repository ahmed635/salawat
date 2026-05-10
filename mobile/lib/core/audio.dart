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
    await _tap.setReleaseMode(ReleaseMode.stop);
    await _tap.setPlayerMode(PlayerMode.lowLatency);
    await _tap.setSource(AssetSource('audio/tap.wav'));

    await _achievement.setReleaseMode(ReleaseMode.stop);
    await _achievement.setPlayerMode(PlayerMode.lowLatency);
    await _achievement.setSource(AssetSource('audio/achievement.wav'));
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
