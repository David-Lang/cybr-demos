export function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

export function printText(value) {
  process.stdout.write(`${value}\n`);
}
