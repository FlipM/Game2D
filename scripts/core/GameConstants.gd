extends Node
# No class_name here if we use it as an Autoload with the same name

# Grid and Movement
const TILE_SIZE: int = 32

# Default Stats
const DEFAULT_MAX_HEALTH: int = 10
const DEFAULT_ATTACK_POWER: int = 1
const DEFAULT_DEFENSE_POWER: int = 0
const DEFAULT_ATTACK_INTERVAL: float = 1.5

# Visuals
const DAMAGE_NUMBER_CENTER_OFFSET: Vector2 = Vector2(-100, -32)
const DAMAGE_NUMBER_SIZE: Vector2 = Vector2(200, 20)

# Networking
const PEER_ID_SERVER: int = 1

# World Geometry
const SCREEN_WIDTH: int = 1152
const SCREEN_HEIGHT: int = 648
const WORLD_CENTER: Vector2 = Vector2(576, 324)

# Entities
const PLAYER_COLOR: Color = Color.RED
const ENEMY_COLOR: Color = Color.WHITE
