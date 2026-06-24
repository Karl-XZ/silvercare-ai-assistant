import fs from 'node:fs';

const appModelPath = 'ios/SilverCareiOS/App/SilverCareAppModel.swift';
const text = fs.readFileSync(appModelPath, 'utf8');

const requiredMarkers = [
  'playSpeechAudio(url: URL, source: String, fallbackText: String)',
  'AVPlayerItemFailedToPlayToEndTime',
  'AVPlayerItemFailedToPlayToEndTimeErrorKey',
  'dashScopeSpeechStatusObservation',
  'item.observe(\\.status',
  'finishSpeechAudioPlayback(source:',
  'failSpeechAudioPlayback(source:',
  'ios_tts_playback_finished',
  'ios_tts_playback_failed',
  'speakWithSystemTTS(fallbackText)',
  'window.LONG_TERM_CARE_TTS_STATE_CHANGED?.(false);'
];

const failures = requiredMarkers.filter((marker) => !text.includes(marker));

if (failures.length > 0) {
  console.error('iOS TTS playback failure handling check failed:');
  for (const marker of failures) {
    console.error(`- missing marker: ${marker}`);
  }
  process.exit(1);
}

console.log('Checked iOS TTS playback end/failure handling and system TTS fallback contract.');
