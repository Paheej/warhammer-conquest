export type Faction = {
  id: string;
  name: string;
  color: string;
  emblem_url: string | null;
  created_at: string;
};

export type Profile = {
  id: string;
  display_name: string;
  faction_id: string | null;
  email: string | null;
  is_admin: boolean;
  created_at: string;
};

export type Planet = {
  id: string;
  name: string;
  description: string | null;
  threshold: number;
  position_x: number;
  position_y: number;
  controlling_faction_id: string | null;
  claimed_at: string | null;
  created_at: string;
};

export type SubmissionType = "game" | "model" | "lore" | "bonus";
export type SubmissionStatus = "pending" | "approved" | "rejected";
export type GameResult = "win" | "loss" | "draw";

export type Submission = {
  id: string;
  player_id: string;
  faction_id: string | null;
  target_planet_id: string | null;
  type: SubmissionType;
  title: string;
  body: string | null;
  image_url: string | null;
  opponent_name: string | null;
  result: GameResult | null;
  points: number;
  status: SubmissionStatus;
  reviewed_by: string | null;
  reviewed_at: string | null;
  review_notes: string | null;
  created_at: string;
};

export type FactionTotal = {
  faction_id: string;
  faction_name: string;
  color: string;
  total_points: number;
  wins: number;
  models_painted: number;
  lore_submitted: number;
  planets_controlled: number;
};

export type PlayerTotal = {
  player_id: string;
  display_name: string;
  faction_id: string | null;
  faction_name: string | null;
  faction_color: string | null;
  total_points: number;
  approved_count: number;
};

export type PlanetPoints = {
  planet_id: string;
  faction_id: string;
  points: number;
};

// Suggested point values per submission type, used in the UI dropdowns
export const POINT_PRESETS: Record<SubmissionType, { label: string; value: number }[]> = {
  game: [
    { label: "Draw", value: 3 },
    { label: "Loss (fought well)", value: 2 },
    { label: "Victory (small game, <1000pts)", value: 5 },
    { label: "Victory (standard, 1000-2000pts)", value: 10 },
    { label: "Victory (grand, 2000pts+)", value: 15 },
  ],
  model: [
    { label: "Single infantry model", value: 2 },
    { label: "Squad (5-10 models)", value: 5 },
    { label: "Vehicle / monster", value: 8 },
    { label: "Character / centerpiece", value: 12 },
  ],
  lore: [
    { label: "Short vignette (<500 words)", value: 3 },
    { label: "Short story (500-1500 words)", value: 6 },
    { label: "Long-form narrative (1500+ words)", value: 10 },
  ],
  bonus: [
    { label: "Small bonus", value: 5 },
    { label: "Medium bonus", value: 10 },
    { label: "Large bonus", value: 20 },
  ],
};
