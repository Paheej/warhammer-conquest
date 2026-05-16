// =====================================================================
// lib/contrast.ts
// Pick a readable foreground color for arbitrary faction colors so
// pills/badges stay legible whether the background is dark purple
// (Eldar seed) or a pale gold someone might pick later.
// =====================================================================

const DARK_INK = '#0a0a14';
const PARCHMENT = '#eadca5';

function hexToRgb(hex: string): [number, number, number] | null {
  const m = hex.replace(/^#/, '').trim();
  const full = m.length === 3 ? m.split('').map((c) => c + c).join('') : m;
  if (full.length !== 6 || !/^[0-9a-fA-F]{6}$/.test(full)) return null;
  return [parseInt(full.slice(0, 2), 16), parseInt(full.slice(2, 4), 16), parseInt(full.slice(4, 6), 16)];
}

function relativeLuminance(rgb: [number, number, number]): number {
  const [r, g, b] = rgb.map((c) => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrastRatio(a: number, b: number): number {
  const [hi, lo] = a > b ? [a, b] : [b, a];
  return (hi + 0.05) / (lo + 0.05);
}

export function readableTextColor(bgHex: string | null | undefined): string {
  const rgb = bgHex ? hexToRgb(bgHex) : null;
  if (!rgb) return PARCHMENT;
  const bgLum = relativeLuminance(rgb);
  const darkLum = relativeLuminance(hexToRgb(DARK_INK)!);
  const lightLum = relativeLuminance(hexToRgb(PARCHMENT)!);
  return contrastRatio(bgLum, darkLum) >= contrastRatio(bgLum, lightLum) ? DARK_INK : PARCHMENT;
}
