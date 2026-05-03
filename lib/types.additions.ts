// =====================================================================
// lib/types.ts — APPEND these to your existing types.ts
// =====================================================================

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

export type LoreFormat = 'novel' | 'audiobook';

export interface ActivityFeedItem {
  submission_id: string;
  kind: 'battle' | 'painted' | 'scribe' | 'loremaster' | 'bonus' | string;
  status: 'approved';
  created_at: string;
  title: string | null;
  description: string | null;
  image_url: string | null;
  points: number | null;
  result: BattleResult | null;
  game_size: GameSize | null;
  lore_title: string | null;
  lore_format: LoreFormat | null;
  lore_rating: number | null;
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
