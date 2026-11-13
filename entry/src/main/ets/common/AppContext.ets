import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** Process-wide handles set by EntryAbility. */
export class AppContext {
  static ctx: common.UIAbilityContext | undefined = undefined;
  static windowStage: window.WindowStage | undefined = undefined;

  static init(ctx: common.UIAbilityContext): void {
    AppContext.ctx = ctx;
  }

  static get(): common.UIAbilityContext {
    if (!AppContext.ctx) {
      throw new Error('AppContext not initialised');
    }
    return AppContext.ctx;
  }
}
