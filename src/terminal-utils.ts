export class TerminalUtils {
  private static lastLineCount = 0;

  static clearLines(count: number): void {
    for (let i = 0; i < count; i++) {
      process.stdout.write('\x1B[1A\x1B[2K');
    }
  }

  static hideCursor(): void {
    process.stdout.write('\x1B[?25l');
  }

  static showCursor(): void {
    process.stdout.write('\x1B[?25h');
  }

  static moveCursorTo(x: number, y: number): void {
    process.stdout.write(`\x1B[${y};${x}H`);
  }

  static clearScreen(): void {
    process.stdout.write('\x1B[2J\x1B[H');
  }

  static updateDisplay(content: string): void {
    const lines = content.split('\n');
    const lineCount = lines.length;

    // Clear previous content
    if (this.lastLineCount > 0) {
      this.moveCursorTo(1, 1);
      process.stdout.write('\x1B[0J');
    }

    // Write new content
    process.stdout.write(content);
    this.lastLineCount = lineCount;
  }
}