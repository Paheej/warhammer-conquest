"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import {
  POINT_PRESETS,
  type Faction,
  type Planet,
  type Profile,
  type SubmissionType,
  type GameResult,
} from "@/lib/types";

const TYPE_LABELS: Record<SubmissionType, { title: string; desc: string }> = {
  game: {
    title: "Battle Report",
    desc: "Record the outcome of a tabletop engagement.",
  },
  model: {
    title: "Painted Unit",
    desc: "Show the work of your brushes. Points awarded per scale.",
  },
  lore: {
    title: "Tale / Lore",
    desc: "A written narrative set in the campaign.",
  },
  bonus: {
    title: "Bonus Claim",
    desc: "Anything else worth rewarding. Admin determines value.",
  },
};

export function SubmitForm({
  profile,
  factions,
  planets,
}: {
  profile: Profile;
  factions: Faction[];
  planets: Planet[];
}) {
  const router = useRouter();
  const [type, setType] = useState<SubmissionType>("game");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [factionId, setFactionId] = useState(profile.faction_id ?? "");
  const [planetId, setPlanetId] = useState("");
  const [opponent, setOpponent] = useState("");
  const [result, setResult] = useState<GameResult>("win");
  const [points, setPoints] = useState(10);
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imageUrl, setImageUrl] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    const supabase = createClient();

    let finalImageUrl = imageUrl || null;

    // If a file was chosen, upload to the 'submissions' bucket first
    if (imageFile) {
      const ext = imageFile.name.split(".").pop() || "jpg";
      const path = `${profile.id}/${Date.now()}.${ext}`;
      const { error: upErr } = await supabase.storage
        .from("submissions")
        .upload(path, imageFile, { upsert: false });
      if (upErr) {
        setError(`Image upload failed: ${upErr.message}`);
        setSubmitting(false);
        return;
      }
      const { data: pub } = supabase.storage.from("submissions").getPublicUrl(path);
      finalImageUrl = pub.publicUrl;
    }

    const { error: insErr } = await supabase.from("submissions").insert({
      player_id: profile.id,
      faction_id: factionId || null,
      target_planet_id: planetId || null,
      type,
      title,
      body: body || null,
      image_url: finalImageUrl,
      opponent_name: type === "game" ? opponent || null : null,
      result: type === "game" ? result : null,
      points: type === "bonus" ? 0 : points, // bonus points set by admin on approval
      status: "pending",
    });

    if (insErr) {
      setError(insErr.message);
      setSubmitting(false);
      return;
    }

    setSuccess(true);
    setSubmitting(false);
    setTimeout(() => router.push("/dashboard"), 1500);
  }

  if (success) {
    return (
      <div className="card p-12 text-center">
        <div className="text-brass text-6xl mb-4">✠</div>
        <h2 className="font-display text-2xl tracking-widest text-parchment">
          YOUR DEED IS SUBMITTED
        </h2>
        <p className="mt-3 font-body italic text-parchment-dim">
          It now awaits the Inquisition's judgement.
        </p>
      </div>
    );
  }

  const presets = POINT_PRESETS[type];

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* Type selector */}
      <div className="card p-6">
        <label className="label mb-3">Nature of the Deed</label>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          {(Object.keys(TYPE_LABELS) as SubmissionType[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setType(t)}
              className={`p-3 border text-left transition-all ${
                type === t
                  ? "border-brass bg-brass/10 text-parchment"
                  : "border-brass/20 text-parchment-dim hover:border-brass/50"
              }`}
            >
              <div className="font-display text-sm tracking-wider">
                {TYPE_LABELS[t].title}
              </div>
            </button>
          ))}
        </div>
        <p className="mt-3 text-sm italic text-parchment-dark">
          {TYPE_LABELS[type].desc}
        </p>
      </div>

      {/* Core fields */}
      <div className="card p-6 space-y-4">
        <div>
          <label className="label">Title</label>
          <input
            type="text"
            required
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="input w-full"
            placeholder={
              type === "game"
                ? "Siege of Prospero"
                : type === "model"
                ? "Terminator Sergeant, Company of Fire"
                : type === "lore"
                ? "The Last Vox from Ferros IX"
                : "Organized a tournament"
            }
          />
        </div>

        <div className="grid md:grid-cols-2 gap-4">
          <div>
            <label className="label">Your Faction</label>
            <select
              required
              value={factionId}
              onChange={(e) => setFactionId(e.target.value)}
              className="input w-full"
            >
              <option value="">— Select —</option>
              {factions.map((f) => (
                <option key={f.id} value={f.id}>
                  {f.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="label">Target World</label>
            <select
              value={planetId}
              onChange={(e) => setPlanetId(e.target.value)}
              className="input w-full"
            >
              <option value="">— No target (glory only) —</option>
              {planets.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Game-specific */}
        {type === "game" && (
          <div className="grid md:grid-cols-2 gap-4">
            <div>
              <label className="label">Opponent</label>
              <input
                type="text"
                value={opponent}
                onChange={(e) => setOpponent(e.target.value)}
                className="input w-full"
                placeholder="Name of your adversary"
              />
            </div>
            <div>
              <label className="label">Outcome</label>
              <select
                value={result}
                onChange={(e) => setResult(e.target.value as GameResult)}
                className="input w-full"
              >
                <option value="win">Victory</option>
                <option value="loss">Defeat</option>
                <option value="draw">Draw</option>
              </select>
            </div>
          </div>
        )}

        {/* Body text */}
        <div>
          <label className="label">
            {type === "lore" ? "The Tale" : "Notes & Narrative"}
          </label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={type === "lore" ? 10 : 4}
            className="input w-full"
            placeholder={
              type === "lore"
                ? "Tell your story. The ledger remembers every word."
                : "Details, unit lists, a brief account…"
            }
          />
        </div>

        {/* Points */}
        {type !== "bonus" && (
          <div>
            <label className="label">Glory Claimed</label>
            <div className="flex flex-wrap gap-2">
              {presets.map((p) => (
                <button
                  key={p.value}
                  type="button"
                  onClick={() => setPoints(p.value)}
                  className={`px-3 py-2 text-sm border font-body ${
                    points === p.value
                      ? "border-brass bg-brass/10 text-brass-bright"
                      : "border-brass/20 text-parchment-dim hover:border-brass/50"
                  }`}
                >
                  {p.label} · <span className="font-display">{p.value}</span>
                </button>
              ))}
            </div>
            <p className="mt-2 text-xs italic text-parchment-dark">
              The Inquisition may adjust this value upon review.
            </p>
          </div>
        )}

        {type === "bonus" && (
          <div className="text-sm italic text-parchment-dim border border-brass/20 bg-brass/5 p-3">
            Bonus submissions have no claimed points — an admin will assign a value on approval.
          </div>
        )}

        {/* Image */}
        <div>
          <label className="label">Image (optional)</label>
          <input
            type="file"
            accept="image/*"
            onChange={(e) => setImageFile(e.target.files?.[0] ?? null)}
            className="input w-full file:bg-brass-dark file:text-parchment file:border-0 file:px-3 file:py-1 file:mr-3 file:font-display file:uppercase file:text-xs file:tracking-wider"
          />
          <div className="mt-3">
            <label className="label">Or paste an image URL</label>
            <input
              type="url"
              value={imageUrl}
              onChange={(e) => setImageUrl(e.target.value)}
              className="input w-full"
              placeholder="https://i.imgur.com/…"
            />
          </div>
        </div>
      </div>

      {error && (
        <div className="text-sm text-crusade font-body border border-crusade/40 bg-crusade/10 p-4">
          {error}
        </div>
      )}

      <div className="flex gap-3 justify-end">
        <button
          type="submit"
          disabled={submitting}
          className="btn-primary disabled:opacity-50"
        >
          {submitting ? "Submitting…" : "Submit for Review"}
        </button>
      </div>
    </form>
  );
}
