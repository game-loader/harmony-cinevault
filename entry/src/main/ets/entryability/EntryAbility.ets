import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../common/AppContext';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.init(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AppContext.windowStage = windowStage;
    windowStage.loadContent('pages/Index');
  }
}
