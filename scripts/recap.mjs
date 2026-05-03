#!/usr/bin/env node
// Usage: node scripts/recap.mjs path/to/crusade-snapshot-*.json > recap.md
//
// Reads a snapshot exported from the admin panel's Season Administration
// section and prints a markdown campaign recap to stdout.

import { readFileSync } from "node:fs";
import { argv, exit } from "node:process";

const path = argv[2];
if (!path) {
  console.error("usage: node scripts/recap.mjs <snapshot.json>");
  exit(1);
}

const snap = JSON.parse(readFileSync(path, "utf8"));

const factions          = snap.factions          ?? [];
const profiles          = snap.profiles          ?? [];
const planets           = snap.planets           ?? [];
const submissions       = snap.submissions       ?? [];
const flips             = snap.planet_flip_log   ?? [];
const awards            = snap.awards            ?? [];
const playerAwards      = snap.player_awards     ?? [];
const factionTotals     = snap.faction_totals    ?? [];
const playerTotals      = snap.player_totals     ?? [];
const eloRatings        = snap.elo_ratings       ?? [];
const planetPoints      = snap.planet_points     ?? [];

const factionById = new Map(factions.map((f) => [f.id, f]));
const profileById = new Map(profiles.map((p) => [p.id, p]));
const awardById   = new Map(awards.map((a) => [a.id, a]));
const planetById  = new Map(planets.map((p) => [p.id, p]));

const out = [];
const w = (line = "") => out.push(line);

const fmtDate = (iso) =>
  iso ? new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }) : "—";

const fmtDateTime = (iso) =>
  iso ? new Date(iso).toLocaleString() : "—";

// ---------- Header ----------
const exportedAt = snap.exported_at ?? new Date().toISOString();
w(`# Crusade Recap`);
w();
w(`Snapshot taken **${fmtDateTime(exportedAt)}**.`);
w();

// ---------- By the Numbers ----------
const approved = submissions.filter((s) => s.status === "approved");
const counts = {
  game:       approved.filter((s) => s.type === "game").length,
  model:      approved.filter((s) => s.type === "model").length,
  scribe:     approved.filter((s) => s.type === "scribe" || s.type === "lore").length,
  loremaster: approved.filter((s) => s.type === "loremaster").length,
  bonus:      approved.filter((s) => s.type === "bonus").length,
};
const totalPoints = approved.reduce((acc, s) => acc + (s.points ?? 0), 0);

w(`## By the Numbers`);
w();
w(`- **${profiles.length}** commanders enlisted`);
w(`- **${factions.length}** factions on the field`);
w(`- **${approved.length}** approved deeds totalling **${totalPoints}** glory`);
w(`- ${counts.game} battles · ${counts.model} models · ${counts.scribe} chronicles · ${counts.loremaster} lore-readings · ${counts.bonus} bonus deeds`);
w(`- **${flips.length}** planet flips logged`);
w();

// ---------- Faction standings ----------
w(`## Final Faction Standings`);
w();
const factionRanked = [...factionTotals].sort(
  (a, b) => (b.total_points ?? 0) - (a.total_points ?? 0)
);
if (factionRanked.length === 0) {
  w(`_No faction data._`);
} else {
  w(`| # | Faction | Glory | Wins | Models | Lore | Worlds |`);
  w(`|---|---------|------:|-----:|-------:|-----:|-------:|`);
  factionRanked.forEach((f, i) => {
    w(
      `| ${i + 1} | ${f.faction_name} | ${f.total_points ?? 0} | ${f.wins ?? 0} | ${f.models_painted ?? 0} | ${f.lore_submitted ?? f.lore_written ?? 0} | ${f.planets_controlled ?? 0} |`
    );
  });
}
w();

// ---------- Player standings ----------
w(`## Final Commander Standings`);
w();
const playerRanked = [...playerTotals]
  .filter((p) => (p.approved_count ?? 0) > 0 || (p.total_points ?? 0) > 0)
  .sort((a, b) => (b.total_points ?? 0) - (a.total_points ?? 0));
if (playerRanked.length === 0) {
  w(`_No commander data._`);
} else {
  w(`| # | Commander | Faction | Glory | Approved Deeds |`);
  w(`|---|-----------|---------|------:|---------------:|`);
  playerRanked.forEach((p, i) => {
    w(
      `| ${i + 1} | ${p.display_name ?? "—"} | ${p.faction_name ?? "—"} | ${p.total_points ?? 0} | ${p.approved_count ?? 0} |`
    );
  });
}
w();

// ---------- Worlds ----------
w(`## Worlds at Season's End`);
w();
const planetsSorted = [...planets].sort((a, b) => a.name.localeCompare(b.name));
if (planetsSorted.length === 0) {
  w(`_No planets._`);
} else {
  w(`| Planet | Controller | Threshold | Claimed | Top Contender |`);
  w(`|--------|------------|----------:|---------|---------------|`);
  planetsSorted.forEach((p) => {
    const controller = p.controlling_faction_id
      ? factionById.get(p.controlling_faction_id)?.name ?? "—"
      : "Contested";
    const top = planetPoints
      .filter((pp) => pp.planet_id === p.id)
      .sort((a, b) => (b.points ?? 0) - (a.points ?? 0))[0];
    const topLabel = top
      ? `${factionById.get(top.faction_id)?.name ?? "?"} (${top.points})`
      : "—";
    w(
      `| ${p.name} | ${controller} | ${p.threshold} | ${fmtDate(p.claimed_at)} | ${topLabel} |`
    );
  });
}
w();

// ---------- Planet flip log ----------
if (flips.length > 0) {
  w(`## Planet Flip Chronicle`);
  w();
  const ordered = [...flips].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  );
  for (const f of ordered) {
    const planet  = planetById.get(f.planet_id)?.name ?? "?";
    const gained  = factionById.get(f.gained_faction_id)?.name ?? "?";
    const lost    = f.lost_faction_id ? factionById.get(f.lost_faction_id)?.name ?? "?" : null;
    const top     = f.top_contributor_id ? profileById.get(f.top_contributor_id)?.display_name ?? "?" : null;
    const stem    = lost
      ? `**${gained}** wrested **${planet}** from **${lost}**`
      : `**${gained}** raised the banner over **${planet}**`;
    const tail    = top ? ` — top contributor: *${top}* (${f.points_at_flip ?? 0} glory at flip)` : "";
    w(`- ${fmtDate(f.created_at)} — ${stem}${tail}.`);
  }
  w();
}

// ---------- Honours Roll ----------
w(`## Honours Roll`);
w();
const awardsByPlayer = new Map();
for (const pa of playerAwards) {
  const list = awardsByPlayer.get(pa.player_id) ?? [];
  list.push(pa);
  awardsByPlayer.set(pa.player_id, list);
}
const honoured = [...awardsByPlayer.entries()]
  .map(([pid, list]) => ({
    player: profileById.get(pid),
    awards: list
      .map((pa) => awardById.get(pa.award_id))
      .filter(Boolean)
      .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0)),
  }))
  .filter((h) => h.player)
  .sort((a, b) => b.awards.length - a.awards.length);

if (honoured.length === 0) {
  w(`_No honours awarded._`);
} else {
  for (const { player, awards } of honoured) {
    w(`### ${player.display_name} — ${awards.length} honour${awards.length === 1 ? "" : "s"}`);
    for (const a of awards) {
      w(`- ${a.icon} **${a.name}** — ${a.description}`);
    }
    w();
  }
}

// ---------- ELO Top 10 ----------
if (eloRatings.length > 0) {
  w(`## Sanctioned Duel Ratings (Top 10)`);
  w();
  const topElo = [...eloRatings]
    .filter((r) => (r.games_played ?? 0) > 0)
    .sort((a, b) => (b.rating ?? 0) - (a.rating ?? 0))
    .slice(0, 10);
  if (topElo.length === 0) {
    w(`_No rated games._`);
  } else {
    w(`| # | Commander | Faction | Rating | W-L-D |`);
    w(`|---|-----------|---------|-------:|-------|`);
    topElo.forEach((r, i) => {
      const player = profileById.get(r.user_id)?.display_name ?? "—";
      const faction = factionById.get(r.faction_id)?.name ?? "—";
      w(
        `| ${i + 1} | ${player} | ${faction} | ${r.rating} | ${r.wins ?? 0}-${r.losses ?? 0}-${r.draws ?? 0} |`
      );
    });
  }
  w();
}

process.stdout.write(out.join("\n") + "\n");
