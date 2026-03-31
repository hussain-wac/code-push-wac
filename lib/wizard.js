'use strict';

const readline = require('readline');

/**
 * Robust cross-platform interactive CLI utilities for devflow.
 */

const COLORS = {
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  white: '\x1b[37m',
  dim: '\x1b[2m',
  reset: '\x1b[0m'
};

function colorize(color, text) {
  return `${COLORS[color] || ''}${text}${COLORS.reset}`;
}

async function askValue(prompt, defaultValue = '', secret = false) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: true
  });

  return new Promise((resolve) => {
    let displayPrompt = `  ${prompt}`;
    if (defaultValue && !secret) {
      displayPrompt += ` [${colorize('dim', defaultValue)}]`;
    }
    displayPrompt += ': ';

    if (secret) {
      process.stdout.write(displayPrompt);
      const stdin = process.stdin;
      let password = '';
      
      const onData = (char) => {
        char = char.toString();
        switch (char) {
          case '\n':
          case '\r':
          case '\u0004': // End of transmission
            stdin.removeListener('data', onData);
            process.stdout.write('\n');
            rl.close();
            resolve(password.trim() || defaultValue);
            break;
          case '\u0003': // Ctrl+C
            process.exit();
            break;
          default:
            // Backspace
            if (char === '\u0008' || char === '\x7f') {
              if (password.length > 0) {
                password = password.slice(0, -1);
              }
            } else {
              password += char;
            }
            break;
        }
      };

      stdin.setRawMode(true);
      stdin.resume();
      stdin.on('data', onData);
    } else {
      rl.question(displayPrompt, (answer) => {
        rl.close();
        resolve(answer.trim() || defaultValue);
      });
    }
  });
}

async function askYesNo(prompt, defaultYes = true) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const suffix = defaultYes ? '(Y/n)' : '(y/N)';
  return new Promise((resolve) => {
    rl.question(`  ${prompt} ${suffix} `, (answer) => {
      rl.close();
      if (!answer) return resolve(defaultYes);
      resolve(/^[Yy]$|yes/i.test(answer));
    });
  });
}

async function selectMenu(title, options, defaultIndex = 0) {
  return new Promise((resolve) => {
    let currentIndex = defaultIndex;
    const stdin = process.stdin;
    
    // Save terminal state
    const isRaw = stdin.isRaw;
    if (stdin.setRawMode) stdin.setRawMode(true);
    readline.emitKeypressEvents(stdin);
    stdin.resume();

    const render = () => {
      // Clear previous lines
      process.stdout.write('\r\x1b[K'); // current line
      for (let i = 0; i < options.length; i++) {
        process.stdout.write('\x1b[1A\r\x1b[K'); // up one line and clear
      }
      process.stdout.write('\x1b[1A\r\x1b[K'); // title line

      // Print menu
      process.stdout.write(`  ${colorize('blue', title)}\n`);
      options.forEach((opt, i) => {
        if (i === currentIndex) {
          process.stdout.write(`  ${colorize('cyan', '❯ ' + opt)}\n`);
        } else {
          process.stdout.write(`    ${opt}\n`);
        }
      });
    };

    // Initial padding for clear
    process.stdout.write('\n'.repeat(options.length + 1));
    render();

    const onKeypress = (str, key) => {
      if (key.name === 'up') {
        currentIndex = (currentIndex - 1 + options.length) % options.length;
        render();
      } else if (key.name === 'down') {
        currentIndex = (currentIndex + 1) % options.length;
        render();
      } else if (key.name === 'return' || key.name === 'enter') {
        cleanup();
        process.stdout.write('\n');
        resolve(options[currentIndex]);
      } else if (key.ctrl && key.name === 'c') {
        cleanup();
        process.exit();
      }
    };

    const cleanup = () => {
      stdin.removeListener('keypress', onKeypress);
      if (stdin.setRawMode) stdin.setRawMode(isRaw);
      stdin.pause();
    };

    stdin.on('keypress', onKeypress);
  });
}

function printBanner(title, emoji = '🛠') {
  console.log('');
  console.log(colorize('cyan', '  ╔════════════════════════════════════════════════════╗'));
  console.log(colorize('cyan', '  ║                                                    ║'));
  console.log(colorize('cyan', `  ║   ${emoji}   devflow-cli — ${title.padEnd(25)}    ║`));
  console.log(colorize('cyan', '  ║                                                    ║'));
  console.log(colorize('cyan', '  ╚════════════════════════════════════════════════════╝'));
  console.log('');
}

function printStep(title) {
  console.log('');
  console.log(colorize('magenta', '  ────────────────────────────────────────────────'));
  console.log(colorize('magenta', `  ${title}`));
  console.log(colorize('magenta', '  ────────────────────────────────────────────────'));
  console.log('');
}

module.exports = {
  COLORS,
  colorize,
  askValue,
  askYesNo,
  selectMenu,
  printBanner,
  printStep
};
