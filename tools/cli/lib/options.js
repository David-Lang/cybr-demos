export function requireOption(options, key) {
  if (!options[key]) {
    throw new Error(`Missing required option: --${key}`);
  }
  return options[key];
}

export function parseBoolean(value, key) {
  if (value === undefined) {
    return false;
  }
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  throw new Error(`Invalid boolean for --${key}: ${value}`);
}
