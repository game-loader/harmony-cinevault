import codecprobe from 'libcodecprobe.so';

/** Raw JSON from the native decoder probe; '[]' if the native library failed to load. */
export function nativeProbeJson(): string {
  try {
    return codecprobe.probe();
  } catch (e) {
    return '[]';
  }
}
