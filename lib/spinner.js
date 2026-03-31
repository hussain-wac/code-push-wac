'use strict';

const { colorize } = require('./wizard');

class Spinner {
  constructor(message) {
    this.message = message;
    this.frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    this.currentFrame = 0;
    this.timer = null;
  }

  start() {
    process.stdout.write('\x1b[?25l'); // Hide cursor
    this.timer = setInterval(() => {
      process.stdout.write(`\r  ${colorize('cyan', this.frames[this.currentFrame])} ${this.message}`);
      this.currentFrame = (this.currentFrame + 1) % this.frames.length;
    }, 80);
  }

  stop(success = true, finalMessage = null) {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    const msg = finalMessage || this.message;
    const symbol = success ? colorize('green', '✓') : colorize('red', '✗');
    process.stdout.write(`\r  ${symbol} ${msg}\n`);
    process.stdout.write('\x1b[?25h'); // Show cursor
  }

  update(message) {
    this.message = message;
  }
}

module.exports = Spinner;
