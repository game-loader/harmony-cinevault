import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../common/AppContext';
import { CodecCaps } from '../media/CodecCaps';
import { AppLog } from '../common/AppLog';
import { bindFlicxLibrary } from '../flicx/FlicxLibraryStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.init(this.context);
    bindFlicxLibrary();
    try {
      // Probe decoders once at startup; result is cached for profile building and the 解码能力 page.
      CodecCaps.load();
    } catch (e) {
      AppLog.error(`[EntryAbility] codec probe failed: ${(e as Error).message}`);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AppContext.windowStage = windowStage;
    windowStage.loadContent('pages/Index');
  }
}
