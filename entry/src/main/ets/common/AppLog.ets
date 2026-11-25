// In-app log: every message also goes to hilog via console, and the last MAX_LINES are kept in memory
// so users without hdc can open 设置 › 运行日志 and copy them.

export class LogLine {
  time: number = 0;
  level: string = 'I';
  text: string = '';
}

const MAX_LINES: number = 1500;
const MAX_TEXT: number = 2000;

function pad(n: number, w: number): string {
  let s = String(n);
  while (s.length < w) {
    s = '0' + s;
  }
  return s;
}

/** Strip query strings and long path tokens so signed media URLs and tokens never land in a copied log. */
export function redact(text: string): string {
  return text
    .replace(/(https?:\/\/[^\s/?#"']+)([^\s?#"']*)\?[^\s"']*/g, '$1$2?…')
    .replace(/\/([A-Za-z0-9_-]{6})[A-Za-z0-9_-]{26,}/g, '/$1…');
}

export function formatLine(l: LogLine): string {
  const d = new Date(l.time);
  return pad(d.getMonth() + 1, 2) + '-' + pad(d.getDate(), 2) + ' ' + pad(d.getHours(), 2) + ':' +
    pad(d.getMinutes(), 2) + ':' + pad(d.getSeconds(), 2) + '.' + pad(d.getMilliseconds(), 3) + ' ' +
    l.level + ' ' + l.text;
}

export class AppLog {
  private static lines: LogLine[] = [];
  private static listeners: Array<() => void> = [];

  static info(text: string): void {
    console.info(text);
    AppLog.add('I', text);
  }

  static warn(text: string): void {
    console.warn(text);
    AppLog.add('W', text);
  }

  static error(text: string): void {
    console.error(text);
    AppLog.add('E', text);
  }

  static all(): LogLine[] {
    return AppLog.lines.slice();
  }

  static clear(): void {
    AppLog.lines = [];
    AppLog.notify();
  }

  /** Plain text for the clipboard, header lines first. */
  static dump(header: string[]): string {
    return header.concat(AppLog.lines.map((l: LogLine) => formatLine(l))).join('\n');
  }

  static onChange(cb: () => void): () => void {
    AppLog.listeners.push(cb);
    return () => {
      AppLog.listeners = AppLog.listeners.filter((x: () => void) => x !== cb);
    };
  }

  private static add(level: string, text: string): void {
    const l = new LogLine();
    l.time = Date.now();
    l.level = level;
    const t = redact(text);
    l.text = t.length > MAX_TEXT ? t.slice(0, MAX_TEXT) + '…' : t;
    AppLog.lines.push(l);
    if (AppLog.lines.length > MAX_LINES) {
      AppLog.lines.splice(0, AppLog.lines.length - MAX_LINES);
    }
    AppLog.notify();
  }

  private static notify(): void {
    AppLog.listeners.forEach((cb: () => void) => {
      try {
        cb();
      } catch (e) {
        // a broken listener must not stop logging
      }
    });
  }
}
