"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import FactionEmblem from "@/components/FactionEmblem";
import AdversaryPicker, { type AdversaryValue } from "@/components/AdversaryPicker";
import type {
  Submission,
  SubmissionType,
  Planet,
  Faction,
  GameSystem,
  GameSystemId,
  GameSize,
  PointScheme,
  VideoGameTitle,
  PlanetGameSystem,
} from "@/lib/types";

type Row = Submission & { profiles: { display_name: string } | null };

const SUBMISSION_TYPE_OPTIONS: { value: SubmissionType; label: string }[] = [
  { value: "game", label: "Battle Report" },
  { value: "model", label: "Painted Unit" },
  { value: "scribe", label: "Scribe" },
  { value: "loremaster", label: "Loremaster" },
  { value: "bonus", label: "Bonus" },
];

const SIZE_LABEL: Record<GameSize, string> = {
  small: "Small",
  standard: "Standard",
  large: "Large",
  "n/a": "N/A",
};

interface GameOverride {
  target_planet_id: string | null;
  game_system_id: GameSystemId | null;
  game_size: GameSize | null;
  video_game_title_id: number | null;
  adversary: AdversaryValue;
}

function initialAdversary(s: Row, factionById: Map<string, Faction>): AdversaryValue {
  return {
    name: s.opponent_name ?? "",
    userId: s.adversary_user_id,
    factionId: s.adversary_faction_id,
    factionName: s.adversary_faction_id ? factionById.get(s.adversary_faction_id)?.name ?? null : null,
  };
}

function initialGame(s: Row, factionById: Map<string, Faction>): GameOverride {
  return {
    target_planet_id: s.target_planet_id,
    game_system_id: (s.game_system_id as GameSystemId | null) ?? null,
    game_size: s.game_size,
    video_game_title_id: s.video_game_title_id,
    adversary: initialAdversary(s, factionById),
  };
}

export function AdminQueue({
  submissions,
  planets,
  factions,
  gameSystems,
  pointSchemes,
  videoGameTitles,
  planetSystems,
}: {
  submissions: Row[];
  planets: Planet[];
  factions: Faction[];
  gameSystems: GameSystem[];
  pointSchemes: PointScheme[];
  videoGameTitles: VideoGameTitle[];
  planetSystems: PlanetGameSystem[];
}) {
  const router = useRouter();
  const [workingId, setWorkingId] = useState<string | null>(null);
  const [adjustments, setAdjustments] = useState<Record<string, number>>({});
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [factionOverrides, setFactionOverrides] = useState<Record<string, string | null>>({});
  const [typeOverrides, setTypeOverrides] = useState<Record<string, SubmissionType>>({});
  const [gameOverrides, setGameOverrides] = useState<Record<string, GameOverride>>({});

  const planetById = new Map(planets.map((p) => [p.id, p]));
  const factionById = new Map(factions.map((f) => [f.id, f]));
  const systemById = new Map(gameSystems.map((g) => [g.id, g]));
  const videoGameById = new Map(videoGameTitles.map((v) => [v.id, v]));
  const sortedFactions = [...factions].sort((a, b) => a.name.localeCompare(b.name));
  const sortedPlanets = [...planets].sort((a, b) => a.name.localeCompare(b.name));

  const allowedSystemsByPlanet = useMemo(() => {
    const map = new Map<string, Set<GameSystemId>>();
    for (const row of planetSystems) {
      const set = map.get(row.planet_id) ?? new Set<GameSystemId>();
      set.add(row.game_system_id);
      map.set(row.planet_id, set);
    }
    return map;
  }, [planetSystems]);

  function allowedSystemsFor(planetId: string | null): GameSystem[] {
    if (!planetId) return gameSystems;
    const set = allowedSystemsByPlanet.get(planetId);
    if (!set || set.size === 0) return gameSystems;
    return gameSystems.filter((s) => set.has(s.id));
  }

  function pointsFor(systemId: GameSystemId | null, size: GameSize | null, result: string | null): number | null {
    if (!systemId || !result) return null;
    const sz = size ?? "n/a";
    const match = pointSchemes.find(
      (ps) => ps.game_system_id === systemId && ps.game_size === sz && ps.result === result,
    );
    return match?.points ?? null;
  }

  function getGameState(s: Row): GameOverride {
    return gameOverrides[s.id] ?? initialGame(s, factionById);
  }

  function setGameState(id: string, patch: Partial<GameOverride>, baseRow: Row) {
    setGameOverrides((prev) => {
      const current = prev[id] ?? initialGame(baseRow, factionById);
      return { ...prev, [id]: { ...current, ...patch } };
    });
  }

  async function review(id: string, status: "approved" | "rejected") {
    setWorkingId(id);
    const supabase = createClient();

    const { data: { user } } = await supabase.auth.getUser();
    const submission = submissions.find((s) => s.id === id);
    if (!submission) {
      setWorkingId(null);
      return;
    }

    const finalPoints = adjustments[id];
    const reviewNote = notes[id] || null;
    const hasFactionOverride = Object.prototype.hasOwnProperty.call(factionOverrides, id);
    const overrideFaction = hasFactionOverride ? factionOverrides[id] : undefined;
    const hasTypeOverride = Object.prototype.hasOwnProperty.call(typeOverrides, id);
    const overrideType = hasTypeOverride ? typeOverrides[id] : undefined;
    const effectiveType = overrideType ?? submission.type;
    const typeChanged = hasTypeOverride && overrideType !== submission.type;
    const hasGameOverride = Object.prototype.hasOwnProperty.call(gameOverrides, id);
    const game = hasGameOverride ? gameOverrides[id] : null;

    const update: Record<string, unknown> = {
      status,
      reviewed_by: user?.id ?? null,
      reviewed_at: new Date().toISOString(),
      review_notes: reviewNote,
    };
    if (status === "approved" && typeof finalPoints === "number") {
      update.points = finalPoints;
    }
    if (hasFactionOverride && overrideFaction !== (submission.faction_id ?? null)) {
      update.faction_id = overrideFaction;
    }
    if (typeChanged && overrideType) {
      update.type = overrideType;
      if (overrideType !== "game") {
        update.result = null;
        update.opponent_name = null;
        update.adversary_user_id = null;
        update.adversary_faction_id = null;
        update.game_system_id = null;
        update.game_size = null;
        update.video_game_title_id = null;
      }
      if (overrideType !== "loremaster") {
        update.lore_title = null;
        update.lore_format = null;
        update.lore_rating = null;
        update.lore_reflection = null;
      }
    }

    if (effectiveType === "game" && game) {
      if (game.target_planet_id !== submission.target_planet_id) {
        update.target_planet_id = game.target_planet_id;
      }
      if (game.game_system_id !== (submission.game_system_id ?? null)) {
        update.game_system_id = game.game_system_id;
      }
      if (game.game_size !== submission.game_size) {
        update.game_size = game.game_size;
      }
      if (game.video_game_title_id !== submission.video_game_title_id) {
        update.video_game_title_id = game.video_game_title_id;
      }
      const newName = game.adversary.name.trim() || null;
      if (newName !== submission.opponent_name) update.opponent_name = newName;
      if (game.adversary.userId !== submission.adversary_user_id) {
        update.adversary_user_id = game.adversary.userId;
      }
      if (game.adversary.factionId !== submission.adversary_faction_id) {
        update.adversary_faction_id = game.adversary.factionId;
      }
    }

    if (status === "approved" && effectiveType === "game") {
      if (game?.adversary.userId && !game.adversary.factionId) {
        setWorkingId(null);
        alert("Pick which faction the linked opponent fielded before approving.");
        return;
      }
    }

    const { error } = await supabase
      .from("submissions")
      .update(update)
      .eq("id", id);

    setWorkingId(null);
    if (error) {
      alert(error.message);
      return;
    }
    router.refresh();
  }

  if (submissions.length === 0) {
    return (
      <div className="card p-10 text-center text-parchment-dim italic">
        The queue is silent. All deeds have been judged.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {submissions.map((s) => {
        const planet = s.target_planet_id ? planetById.get(s.target_planet_id) : null;
        const hasFactionOverride = Object.prototype.hasOwnProperty.call(factionOverrides, s.id);
        const selectedFactionId = hasFactionOverride ? factionOverrides[s.id] : s.faction_id;
        const faction = selectedFactionId ? factionById.get(selectedFactionId) : null;
        const factionChanged = hasFactionOverride && selectedFactionId !== s.faction_id;
        const hasTypeOverride = Object.prototype.hasOwnProperty.call(typeOverrides, s.id);
        const selectedType = hasTypeOverride ? typeOverrides[s.id] : s.type;
        const typeChanged = hasTypeOverride && selectedType !== s.type;
        const adjusted = adjustments[s.id] ?? s.points;
        const game = getGameState(s);
        const currentSystem = game.game_system_id ? systemById.get(game.game_system_id) ?? null : null;
        const allowedSystems = allowedSystemsFor(game.target_planet_id);
        const suggestedPoints = pointsFor(game.game_system_id, game.game_size, s.result);
        const battleEditable = selectedType === "game";

        return (
          <div key={s.id} className="card p-6">
            <div className="flex flex-wrap items-start justify-between gap-4 mb-4">
              <div>
                <div className="flex items-center gap-3 mb-1 flex-wrap">
                  <span className="font-display text-xs uppercase tracking-widest text-brass px-2 py-0.5 border border-brass/40">
                    {selectedType}
                  </span>
                  {s.type === "game" && s.result && (
                    <span
                      className={`font-display text-xs uppercase tracking-widest px-2 py-0.5 border ${
                        s.result === "win"
                          ? "border-brass-bright text-brass-bright"
                          : s.result === "loss"
                          ? "border-crusade text-crusade"
                          : "border-parchment-dim text-parchment-dim"
                      }`}
                    >
                      {s.result}
                    </span>
                  )}
                  {s.type === "loremaster" && s.lore_format && (
                    <span className="inline-flex items-center gap-1 rounded-full border border-indigo-700/60 bg-indigo-900/30 px-2 py-0.5 text-xs font-medium text-indigo-200">
                      <span aria-hidden>{s.lore_format === "novel" ? "📕" : "🎧"}</span>
                      {s.lore_format === "novel" ? "Novel" : "Audiobook"}
                    </span>
                  )}
                  {s.type === "loremaster" && s.lore_rating !== null && (
                    <span className="text-sm text-brass-bright" aria-label={`${s.lore_rating} out of 5`}>
                      {Array.from({ length: 5 }).map((_, i) => (i < (s.lore_rating ?? 0) ? "★" : "☆")).join("")}
                    </span>
                  )}
                </div>
                <h3 className="font-display text-xl text-parchment">{s.title}</h3>
                <div className="mt-1 text-sm text-parchment-dim font-body">
                  by <span className="text-parchment">{s.profiles?.display_name ?? "Unknown"}</span>
                  {faction && (
                    <>
                      {' · '}
                      <span className="inline-flex items-center gap-1 align-middle">
                        {faction.emblem_url && (
                          <FactionEmblem url={faction.emblem_url} color={faction.color} size={12} />
                        )}
                        <span style={{ color: faction.color }}>{faction.name}</span>
                      </span>
                    </>
                  )}
                  {planet && <> · targeting <span className="text-brass">{planet.name}</span></>}
                  {s.opponent_name && <> · vs {s.opponent_name}</>}
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-parchment-dark uppercase tracking-wider">Claimed</div>
                <div className="font-display text-2xl text-brass-bright">{s.points}</div>
              </div>
            </div>

            {s.body && (
              <div className="mb-4 p-4 bg-ink border border-brass/10 font-body text-parchment-dim whitespace-pre-wrap max-h-48 overflow-y-auto">
                {s.body}
              </div>
            )}

            {s.image_url && (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img
                src={s.image_url}
                alt={s.title}
                className="mb-4 max-h-80 border border-brass/20"
              />
            )}

            <div className="pt-4 border-t border-brass/10 space-y-4">
              <div className="grid md:grid-cols-3 gap-4">
                <div>
                  <label className="label">Adjust Points</label>
                  <input
                    type="number"
                    min={0}
                    value={adjusted}
                    onChange={(e) =>
                      setAdjustments((a) => ({
                        ...a,
                        [s.id]: Number(e.target.value),
                      }))
                    }
                    className="input w-full"
                  />
                  {battleEditable && suggestedPoints !== null && suggestedPoints !== adjusted && (
                    <button
                      type="button"
                      onClick={() => setAdjustments((a) => ({ ...a, [s.id]: suggestedPoints }))}
                      className="mt-1 text-xs text-brass hover:text-brass-bright underline"
                    >
                      Use scheme suggestion: {suggestedPoints}
                    </button>
                  )}
                </div>
                <div>
                  <label className="label">
                    Type
                    {typeChanged && (
                      <span className="ml-2 text-xs text-crusade normal-case tracking-normal">
                        changed
                      </span>
                    )}
                  </label>
                  <select
                    value={selectedType}
                    onChange={(e) =>
                      setTypeOverrides((t) => ({
                        ...t,
                        [s.id]: e.target.value as SubmissionType,
                      }))
                    }
                    className="input w-full"
                  >
                    {SUBMISSION_TYPE_OPTIONS.map((opt) => (
                      <option key={opt.value} value={opt.value} className="bg-ink text-parchment">
                        {opt.label}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="label">
                    Faction
                    {factionChanged && (
                      <span className="ml-2 text-xs text-crusade normal-case tracking-normal">
                        changed
                      </span>
                    )}
                  </label>
                  <select
                    value={selectedFactionId ?? ""}
                    onChange={(e) =>
                      setFactionOverrides((f) => ({
                        ...f,
                        [s.id]: e.target.value === "" ? null : e.target.value,
                      }))
                    }
                    className="input w-full"
                  >
                    <option value="" className="bg-ink text-parchment">
                      (no faction)
                    </option>
                    {sortedFactions.map((f) => (
                      <option key={f.id} value={f.id} className="bg-ink text-parchment">
                        {f.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {battleEditable && (
                <div className="rounded border border-brass/20 bg-ink/40 p-4 space-y-4">
                  <div className="font-display uppercase tracking-widest text-xs text-brass-bright">
                    Battle Details
                  </div>

                  <div className="grid md:grid-cols-3 gap-4">
                    <div>
                      <label className="label">Planet</label>
                      <select
                        value={game.target_planet_id ?? ""}
                        onChange={(e) => {
                          const newPlanetId = e.target.value === "" ? null : e.target.value;
                          const newAllowed = allowedSystemsFor(newPlanetId);
                          const stillAllowed =
                            game.game_system_id && newAllowed.some((sys) => sys.id === game.game_system_id);
                          const snappedSystem: GameSystemId | null = stillAllowed
                            ? game.game_system_id
                            : newAllowed[0]?.id ?? null;
                          const snappedSystemDef = snappedSystem ? systemById.get(snappedSystem) : null;
                          const snappedSize: GameSize | null = snappedSystemDef
                            ? snappedSystemDef.supports_size
                              ? game.game_size && game.game_size !== "n/a"
                                ? game.game_size
                                : "standard"
                              : "n/a"
                            : game.game_size;
                          const snappedVg: number | null = snappedSystemDef?.supports_video_game
                            ? game.video_game_title_id
                            : null;
                          setGameState(
                            s.id,
                            {
                              target_planet_id: newPlanetId,
                              game_system_id: snappedSystem,
                              game_size: snappedSize,
                              video_game_title_id: snappedVg,
                            },
                            s,
                          );
                        }}
                        className="input w-full"
                      >
                        <option value="" className="bg-ink text-parchment">
                          (no planet)
                        </option>
                        {sortedPlanets.map((p) => (
                          <option key={p.id} value={p.id} className="bg-ink text-parchment">
                            {p.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <label className="label">Game System</label>
                      <select
                        value={game.game_system_id ?? ""}
                        onChange={(e) => {
                          const newId = (e.target.value || null) as GameSystemId | null;
                          const def = newId ? systemById.get(newId) : null;
                          const newSize: GameSize | null = def
                            ? def.supports_size
                              ? game.game_size && game.game_size !== "n/a"
                                ? game.game_size
                                : "standard"
                              : "n/a"
                            : null;
                          const newVg: number | null = def?.supports_video_game
                            ? game.video_game_title_id
                            : null;
                          setGameState(
                            s.id,
                            { game_system_id: newId, game_size: newSize, video_game_title_id: newVg },
                            s,
                          );
                        }}
                        className="input w-full"
                      >
                        <option value="" className="bg-ink text-parchment">
                          — select —
                        </option>
                        {allowedSystems.map((sys) => (
                          <option key={sys.id} value={sys.id} className="bg-ink text-parchment">
                            {sys.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <label className="label">Battle Size</label>
                      <select
                        value={game.game_size ?? ""}
                        disabled={!currentSystem || !currentSystem.supports_size}
                        onChange={(e) =>
                          setGameState(
                            s.id,
                            { game_size: (e.target.value || null) as GameSize | null },
                            s,
                          )
                        }
                        className="input w-full disabled:opacity-60"
                      >
                        {currentSystem?.supports_size ? (
                          (["small", "standard", "large"] as GameSize[]).map((sz) => (
                            <option key={sz} value={sz} className="bg-ink text-parchment">
                              {SIZE_LABEL[sz]}
                            </option>
                          ))
                        ) : (
                          <option value={game.game_size ?? "n/a"} className="bg-ink text-parchment">
                            {SIZE_LABEL[game.game_size ?? "n/a"]}
                          </option>
                        )}
                      </select>
                    </div>
                  </div>

                  {currentSystem?.supports_video_game && (
                    <div>
                      <label className="label">Video Game</label>
                      <select
                        value={game.video_game_title_id ?? ""}
                        onChange={(e) =>
                          setGameState(
                            s.id,
                            { video_game_title_id: e.target.value === "" ? null : Number(e.target.value) },
                            s,
                          )
                        }
                        className="input w-full"
                      >
                        <option value="" className="bg-ink text-parchment">
                          — select a title —
                        </option>
                        {videoGameTitles.map((v) => (
                          <option key={v.id} value={v.id} className="bg-ink text-parchment">
                            {v.name}
                          </option>
                        ))}
                      </select>
                      {game.video_game_title_id && (
                        <p className="mt-1 text-xs italic text-parchment-dark">
                          Approving will rate ELO for {videoGameById.get(game.video_game_title_id)?.name ?? "this title"}.
                        </p>
                      )}
                    </div>
                  )}

                  <AdversaryPicker
                    value={game.adversary}
                    onChange={(v) => setGameState(s.id, { adversary: v }, s)}
                    currentUserId={s.player_id}
                  />
                </div>
              )}

              <div>
                <label className="label">Review Notes (optional)</label>
                <input
                  type="text"
                  value={notes[s.id] ?? ""}
                  onChange={(e) =>
                    setNotes((n) => ({ ...n, [s.id]: e.target.value }))
                  }
                  className="input w-full"
                  placeholder="Reason for rejection, or a commendation…"
                />
              </div>
              {typeChanged && (
                <p className="text-xs italic text-parchment-dark">
                  Type changed from <span className="text-parchment">{s.type}</span> to <span className="text-parchment">{selectedType}</span>. Any type-specific fields (battle result, lore rating, etc.) will be cleared on save.
                </p>
              )}
            </div>

            <div className="flex gap-3 justify-end mt-4">
              <button
                onClick={() => review(s.id, "rejected")}
                disabled={workingId === s.id}
                className="btn-danger disabled:opacity-50"
              >
                Reject
              </button>
              <button
                onClick={() => review(s.id, "approved")}
                disabled={workingId === s.id}
                className="btn-primary disabled:opacity-50"
              >
                {workingId === s.id ? "Sealing…" : "Approve"}
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}
