extends Node
# No class_name here if we use it as an Autoload with the same name

# ---------------------------------------------------------------------------
# Grid and World Geometry
# ---------------------------------------------------------------------------
const TILE_SIZE: int        = 32
const SCREEN_WIDTH: int     = 1152
const SCREEN_HEIGHT: int    = 648
const WORLD_CENTER: Vector2 = Vector2(576, 324)

# Arena dimensions (in tiles from centre, inclusive).
# BOUNDARY_RADIUS = ARENA_RADIUS + 1 (one ring of walls outside the floor).
const ARENA_RADIUS: int    = 8
const BOUNDARY_RADIUS: int = 9

# ---------------------------------------------------------------------------
# Pathfinding
# ---------------------------------------------------------------------------
# Diagonal moves cost slightly more than 2 orthogonal steps so the pathfinder
# prefers straight lines but will use diagonals to avoid long detours.
const ASTAR_DIAGONAL_COST: float = 2.01
const ASTAR_ORTHOGONAL_COST: float = 1.0

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
# Diagonal travel is slower: speed is multiplied by this factor.
const DIAGONAL_SPEED_FACTOR: float = 0.7
# Minimum per-frame displacement before a moving entity is considered "stuck".
const STUCK_MIN_DISPLACEMENT: float = 0.1
# Seconds without progress before movement is aborted and entity is snapped.
const STUCK_TIMEOUT: float = 0.8
# World-space distance threshold for "arrived at tile centre".
const ARRIVAL_THRESHOLD: float = 2.0
# Axis threshold used to detect diagonal movement direction.
const DIAGONAL_AXIS_THRESHOLD: float = 0.1

# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------
const MELEE_RANGE_MULTIPLIER: float = 1.6

# ---------------------------------------------------------------------------
# Default entity stats
# ---------------------------------------------------------------------------
const DEFAULT_MAX_HEALTH: int      = 10
const DEFAULT_ATTACK_POWER: int    = 1
const DEFAULT_DEFENSE_POWER: int   = 0
const DEFAULT_ATTACK_INTERVAL: float = 1.5

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
const PEER_ID_SERVER: int = 1

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------
const PLAYER_COLOR: Color = Color.RED
const ENEMY_COLOR: Color  = Color.WHITE
const DAMAGE_NUMBER_CENTER_OFFSET: Vector2 = Vector2(-100, -32)
const DAMAGE_NUMBER_SIZE: Vector2          = Vector2(200, 20)
