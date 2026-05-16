// =====================================================================
// components/FactionEmblem.tsx
// Renders a monochrome SVG faction emblem tinted with the faction's
// color via CSS mask-image. Used on the orbital map (planet badge,
// side panel chips) and the home activity feed pill.
// =====================================================================

import type { CSSProperties } from 'react';

interface Props {
  url: string;
  color: string;
  size?: number;
  className?: string;
  title?: string;
}

export default function FactionEmblem({ url, color, size = 16, className = '', title }: Props) {
  const style: CSSProperties = {
    width: size,
    height: size,
    backgroundColor: color,
    WebkitMaskImage: `url(${url})`,
    maskImage: `url(${url})`,
    WebkitMaskRepeat: 'no-repeat',
    maskRepeat: 'no-repeat',
    WebkitMaskSize: 'contain',
    maskSize: 'contain',
    WebkitMaskPosition: 'center',
    maskPosition: 'center',
  };
  return <span aria-hidden={!title} role={title ? 'img' : undefined} aria-label={title} className={`inline-block shrink-0 ${className}`} style={style} />;
}
