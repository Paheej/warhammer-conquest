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
    { label: "Character / Single Infantry Model", value: 2 },
    { label: "Fireteam (3-5 models)", value: 5 },
    { label: "Squad (6-10 models)", value: 10 },
    { label: "Horde (11+ models)", value: 20 },
    { label: "Vehicle / monster", value: 8 },
    { label: "Titanic", value: 25 },
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


export const GAME_SYSTEMS = {
  '40k_3':  '3rd Edition 40K',
  '40k_10': '10th/11th Edition 40K',
  'bfg':    'Battlefleet Gothic',
  'epic':   'Epic 40K',
  'video':  'Video Games',
} as const;

export type GameSystemId = keyof typeof GAME_SYSTEMS;

export const DEFAULT_GAME_SYSTEM: GameSystemId = '40k_10';

export type GameSize = 'small' | 'standard' | 'large' | 'n/a';

export const GAME_SIZE_LABELS: Record<GameSize, string> = {
  small:    'Small (Combat Patrol / Boarding Action)',
  standard: 'Standard (Incursion)',
  large:    'Large (Strike Force / Apocalypse)',
  'n/a':    'N/A',
};

export type BattleResult = 'loss' | 'draw' | 'win';

export const BATTLE_RESULT_LABELS: Record<BattleResult, string> = {
  loss: 'Loss',
  draw: 'Draw',
  win:  'Win',
};

export interface GameSystem {
  id: GameSystemId;
  name: string;
  short_name: string;
  supports_size: boolean;
  supports_video_game: boolean;
  sort_order: number;
  is_default: boolean;
}

export interface PointScheme {
  id: number;
  game_system_id: GameSystemId;
  game_size: GameSize;
  result: BattleResult;
  points: number;
}

export interface VideoGameTitle {
  id: number;
  name: string;
  sort_order: number;
}

export interface PlanetGameSystem {
  planet_id: string;
  game_system_id: GameSystemId;
}

export interface PlayerFaction {
  user_id: string;
  faction_id: string;
  is_primary: boolean;
  joined_at: string;
}

export interface EloRating {
  user_id: string;
  game_system_id: GameSystemId;
  faction_id: string;
  rating: number;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
  updated_at: string;
}

export interface EloConfig {
  game_system_id: GameSystemId;
  starting_elo: number;
  k_factor: number;
}

export interface ActivityFeedItem {
  submission_id: string;
  kind: 'battle' | 'painted' | 'lore' | 'bonus' | string;
  status: 'approved';
  created_at: string;
  title: string | null;
  description: string | null;
  image_url: string | null;
  points: number | null;
  result: BattleResult | null;
  game_size: GameSize | null;
  user_id: string | null;
  display_name: string;
  avatar_url: string | null;
  faction_id: string | null;
  faction_name: string | null;
  faction_color: string | null;
  planet_id: string | null;
  planet_name: string | null;
  game_system_id: GameSystemId | null;
  game_system_short: string | null;
  game_system_name: string | null;
  adversary_user_id: string | null;
  adversary_name: string | null;
  adversary_faction_name: string | null;
  adversary_faction_color: string | null;
  video_game_name: string | null;
}

export interface SearchablePlayer {
  id: string;
  display_name: string;
  avatar_url: string | null;
  primary_faction_id: string | null;
  primary_faction_name: string | null;
}
