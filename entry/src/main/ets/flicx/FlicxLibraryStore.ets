// Binds FlicxLibrary to ArkData preferences. Imported once at startup (EntryAbility).
import { preferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';
import { AppLog } from '../common/AppLog';
import { FlicxLibrary } from './FlicxLibrary';

const PREF_NAME: string = 'flicx_library';
const KEY: string = 'items';

let store: preferences.Preferences | undefined = undefined;

async function open(): Promise<preferences.Preferences> {
  if (store === undefined) {
    store = await preferences.getPreferences(AppContext.get(), PREF_NAME);
  }
  return store;
}

export function bindFlicxLibrary(): void {
  FlicxLibrary.readText = async (): Promise<string> => {
    try {
      return (await open()).getSync(KEY, '') as string;
    } catch (e) {
      AppLog.error(`[FlicxLibrary] read failed: ${(e as Error).message}`);
      return '';
    }
  };
  FlicxLibrary.writeText = async (text: string): Promise<void> => {
    try {
      const p = await open();
      p.putSync(KEY, text);
      await p.flush();
    } catch (e) {
      AppLog.error(`[FlicxLibrary] save failed: ${(e as Error).message}`);
    }
  };
}
