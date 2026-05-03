// Accepts either UI vocabulary (battle/painted) emitted by the activity_feed
// view, or the raw DB enum (game/model) read from the submissions table.
// See migration 0003_submission_kind_alignment.sql for the mapping.
const ALIAS: Record<string, string> = { game: 'battle', model: 'painted' };

export default function KindBadge({ kind }: { kind: string }) {
  const normalized = ALIAS[kind] ?? kind;
  const map: Record<string, { label: string; cls: string; icon: string }> = {
    battle:     { label: 'Battle',     cls: 'border-red-700/60    bg-red-900/30    text-red-200',    icon: '⚔' },
    painted:    { label: 'Painted',    cls: 'border-blue-700/60   bg-blue-900/30   text-blue-200',   icon: '🖌' },
    scribe:     { label: 'Scribe',     cls: 'border-amber-700/60  bg-amber-900/30  text-amber-200',  icon: '📜' },
    loremaster: { label: 'Loremaster', cls: 'border-indigo-700/60 bg-indigo-900/30 text-indigo-200', icon: '📖' },
    bonus:      { label: 'Bonus',      cls: 'border-purple-700/60 bg-purple-900/30 text-purple-200', icon: '✦' },
  };
  const cfg = map[normalized] ?? { label: normalized, cls: 'border-brass/40 bg-brass/20 text-brass-bright', icon: '✠' };
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium ${cfg.cls}`}>
      <span aria-hidden>{cfg.icon}</span> {cfg.label}
    </span>
  );
}
