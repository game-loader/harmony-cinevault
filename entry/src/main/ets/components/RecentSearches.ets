import { preferences } from '@kit.ArkData';
import { AppContext } from '../common/AppContext';
import { pushRecent, parseRecent } from './MediaLogic';

const PREF = 'search';
const KEY = 'recent';
const CAP = 15;

/** Recent search terms persisted in preferences ('search'). */
export class RecentSearches {
  private static store: preferences.Preferences | undefined = undefined;

  private static async pref(): Promise<preferences.Preferences> {
    if (RecentSearches.store === undefined) {
      RecentSearches.store = await preferences.getPreferences(AppContext.get(), PREF);
    }
    return RecentSearches.store;
  }

  static async list(): Promise<string[]> {
    try {
      const p = await RecentSearches.pref();
      return parseRecent(p.getSync(KEY, '[]') as string);
    } catch (e) {
      return [];
    }
  }

  private static async write(list: string[]): Promise<void> {
    try {
      const p = await RecentSearches.pref();
      p.putSync(KEY, JSON.stringify(list));
      await p.flush();
    } catch (e) {
      // best effort
    }
  }

  static async add(term: string): Promise<string[]> {
    const next = pushRecent(await RecentSearches.list(), term, CAP);
    await RecentSearches.write(next);
    return next;
  }

  static async remove(term: string): Promise<string[]> {
    const next = (await RecentSearches.list()).filter((s: string) => s !== term);
    await RecentSearches.write(next);
    return next;
  }

  static async clear(): Promise<void> {
    await RecentSearches.write([]);
  }
}
