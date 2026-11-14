import { deviceInfo } from '@kit.BasicServicesKit';
import { nativeProbeJson } from './NativeProbe';
import {
  CodecEntry, DecoderInfo, parseProbeJson, findEntry, hasDecoder, hasHardware, maxHeightOf, pickDecoder, formatReport
} from './ProfileBuilder';

// The data classes live in the pure ProfileBuilder module so they can be unit-tested; re-exported here (contract).
export { CodecEntry, DecoderInfo };

/**
 * OWNER: codec agent. Facade over the native probe. load() runs the (read-only, fast) probe and caches the result;
 * call it once at startup (EntryAbility) and again to re-detect. entries() and the queries use the cache and probe
 * lazily the first time. Signatures below are the contract other modules use.
 */
export class CodecCaps {
  private static cache: CodecEntry[] = [];
  private static loaded: boolean = false;

  static load(): CodecEntry[] {
    let json = '[]';
    try {
      json = nativeProbeJson();
    } catch (e) {
      console.error(`[CodecCaps] probe failed: ${(e as Error).message}`);
    }
    CodecCaps.cache = parseProbeJson(json);
    CodecCaps.loaded = true;
    return CodecCaps.cache;
  }

  static entries(): CodecEntry[] {
    if (!CodecCaps.loaded) {
      return CodecCaps.load();
    }
    return CodecCaps.cache;
  }

  static has(codec: string): boolean {
    return hasDecoder(CodecCaps.entries(), codec);
  }

  static isHardware(codec: string): boolean {
    return hasHardware(CodecCaps.entries(), codec);
  }

  /** Largest height any decoder for this codec supports (0 = none) */
  static maxHeight(codec: string): number {
    return maxHeightOf(CodecCaps.entries(), codec);
  }

  /** Decoder that would be used for this codec (hardware preferred), undefined if none */
  static decoderFor(codec: string): DecoderInfo | undefined {
    return pickDecoder(CodecCaps.entries(), codec);
  }

  /** Probe entry for a codec (aliases like h265/dca accepted), undefined if the codec wasn't probed */
  static entry(codec: string): CodecEntry | undefined {
    return findEntry(CodecCaps.entries(), codec);
  }

  /** Plain-text report for the "复制报告" button */
  static report(): string {
    const header: string[] = ['影库 解码能力报告'];
    try {
      header.push('设备: ' + deviceInfo.marketName + ' (' + deviceInfo.productModel + ')');
      header.push('系统: ' + deviceInfo.osFullName + ' / API ' + deviceInfo.sdkApiVersion);
    } catch (e) {
      console.warn(`[CodecCaps] deviceInfo unavailable: ${(e as Error).message}`);
    }
    return formatReport(CodecCaps.entries(), header);
  }
}
