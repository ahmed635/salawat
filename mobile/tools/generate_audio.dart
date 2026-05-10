// Generates the two short WAV files used by the app at runtime.
// Faithfully reproduces the Web Audio API parameters from the React source
// (sallou-app.jsx) so the Flutter app sounds identical.
//
// Run from the `mobile/` directory:
//   dart run tools/generate_audio.dart
//
// Outputs assets/audio/tap.wav and assets/audio/achievement.wav. Re-run any
// time you tweak the parameters below.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  final dir = Directory('assets/audio');
  dir.createSync(recursive: true);

  final tap = _generateTap();
  File('${dir.path}/tap.wav').writeAsBytesSync(tap);
  print('Wrote ${dir.path}/tap.wav (${tap.length} bytes)');

  final ach = _generateAchievement();
  File('${dir.path}/achievement.wav').writeAsBytesSync(ach);
  print('Wrote ${dir.path}/achievement.wav (${ach.length} bytes)');
}

/// Sine 800Hz → 300Hz (exponential ramp), gain 0.05 → 0.001 over 100 ms.
Uint8List _generateTap() {
  const duration = 0.1;
  final n = (_sampleRate * duration).round();
  final samples = Float64List(n);

  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final freq = 800 * pow(300 / 800, t / duration);
    final gain = 0.05 * pow(0.001 / 0.05, t / duration);
    samples[i] = sin(phase) * gain;
    phase += 2 * pi * freq / _sampleRate;
  }
  return _encodeWav(samples);
}

/// Triangle wave, four ascending notes (C5, E5, G5, C6) at 100ms intervals,
/// gain 0.1 → 0.00001 exponential decay over 800 ms.
Uint8List _generateAchievement() {
  const duration = 0.8;
  const noteStep = 0.1;
  const notes = <double>[523.25, 659.25, 783.99, 1046.50];
  final n = (_sampleRate * duration).round();
  final samples = Float64List(n);

  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    final noteIndex = min((t / noteStep).floor(), notes.length - 1);
    final freq = notes[noteIndex];
    // Triangle wave: in [-1, 1]
    final cyclePos = (phase / (2 * pi)) % 1.0;
    final tri = (cyclePos < 0.5)
        ? (4 * cyclePos - 1)
        : (3 - 4 * cyclePos);
    final gain = 0.1 * pow(0.00001 / 0.1, t / duration);
    samples[i] = tri * gain;
    phase += 2 * pi * freq / _sampleRate;
  }
  return _encodeWav(samples);
}

/// Mono 16-bit PCM WAV at 44.1 kHz.
Uint8List _encodeWav(Float64List samples) {
  final n = samples.length;
  final out = ByteData(44 + n * 2);

  // RIFF header
  out.setUint8(0, 0x52); // R
  out.setUint8(1, 0x49); // I
  out.setUint8(2, 0x46); // F
  out.setUint8(3, 0x46); // F
  out.setUint32(4, 36 + n * 2, Endian.little);
  out.setUint8(8, 0x57); // W
  out.setUint8(9, 0x41); // A
  out.setUint8(10, 0x56); // V
  out.setUint8(11, 0x45); // E

  // fmt chunk
  out.setUint8(12, 0x66); // f
  out.setUint8(13, 0x6d); // m
  out.setUint8(14, 0x74); // t
  out.setUint8(15, 0x20); // ' '
  out.setUint32(16, 16, Endian.little); // chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, _sampleRate, Endian.little);
  out.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample

  // data chunk
  out.setUint8(36, 0x64); // d
  out.setUint8(37, 0x61); // a
  out.setUint8(38, 0x74); // t
  out.setUint8(39, 0x61); // a
  out.setUint32(40, n * 2, Endian.little);

  for (var i = 0; i < n; i++) {
    final s = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, s, Endian.little);
  }

  return out.buffer.asUint8List();
}
