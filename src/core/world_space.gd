class_name WorldSpace
extends Object
## The only place in the project that converts between world space and screen
## space. Oblique 3/4 projection, per GAME_DESIGN.md.
##
## World space is measured in world units (wu): x runs east, y runs south into
## the screen, z runs up. One wu is one grid cell and, by the canonical scale,
## about one metre.
##
##     screen.x = x * GROUND_PX
##     screen.y = y * GROUND_PX * DEPTH_RATIO  -  z * HEIGHT_PX
##
## There is no rotation, only foreshortening of the depth axis -- that is what
## makes this oblique rather than isometric, and it is why the inverse is exact
## and needs no matrix. Setting DEPTH_RATIO to 1.0 turns it into plain top-down
## and every caller follows, because nothing else does this arithmetic.
##
## Static only; never instantiated. Deliberately free of nodes and SceneTree so
## it can be unit-tested without rendering anything.


# --- Scale ------------------------------------------------------------------

## Screen pixels per world unit along x (and along the un-foreshortened axis).
static func ground_px() -> float:
	return float(GameConstants.GROUND_PX_PER_UNIT)


## Screen pixels per world unit along the depth axis (y). Shorter than
## [method ground_px], which is what tilts the ground plane.
static func depth_px() -> float:
	return ground_px() * GameConstants.DEPTH_RATIO


## Screen pixels per world unit of elevation.
static func height_px() -> float:
	return float(GameConstants.HEIGHT_PX_PER_UNIT)


# --- Projection -------------------------------------------------------------

## Projects a full 3D world position, elevation included.
static func world_to_screen(world: Vector3) -> Vector2:
	return Vector2(
		world.x * ground_px(),
		world.y * depth_px() - world.z * height_px()
	)


## Projects a point on the ground plane (z = 0).
static func ground_to_screen(ground: Vector2) -> Vector2:
	return Vector2(ground.x * ground_px(), ground.y * depth_px())


## Inverse of [method ground_to_screen]. Exact, because the projection is a
## pure axis scaling. Any elevation in the source point is read as depth, so
## only pass screen positions known to lie on the ground.
static func screen_to_ground(screen: Vector2) -> Vector2:
	return Vector2(screen.x / ground_px(), screen.y / depth_px())


## How far up the screen an object sits when raised [param z] world units.
## Added to a ground projection rather than baked into it, so a sprite can be
## lifted visually without moving its logical position on the ground.
static func elevation_offset(z: float) -> Vector2:
	return Vector2(0.0, -z * height_px())


# --- Grid -------------------------------------------------------------------

## The cell containing a ground point. One cell is one world unit square.
static func ground_to_cell(ground: Vector2) -> Vector2i:
	return Vector2i(floori(ground.x), floori(ground.y))


## Centre of a cell, in ground coordinates.
static func cell_centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## Minimum corner of a cell, in ground coordinates.
static func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell)


# --- Footprints -------------------------------------------------------------

## The ground rectangle an object occupies. [param anchor] is normalised within
## the footprint: (0.5, 0.5) centres it on [param ground], (0.5, 1.0) puts the
## object's front edge there.
##
## This is the logical footprint -- the only rectangle gameplay rules may use.
## Visual bounds are a separate concern and never feed back into it.
static func footprint_rect(ground: Vector2, footprint: Vector2,
		anchor: Vector2 = Vector2(0.5, 0.5)) -> Rect2:
	return Rect2(ground - footprint * anchor, footprint)


## Screen size of a footprint, foreshortened along the depth axis. Used to
## build collision and interaction shapes from data instead of by hand.
static func footprint_screen_size(footprint: Vector2) -> Vector2:
	return Vector2(footprint.x * ground_px(), footprint.y * depth_px())


# --- Draw order -------------------------------------------------------------

## Sort key for draw order: the screen y of an object's ground contact point,
## with elevation deliberately ignored.
##
## Sorting by sprite position instead would put a tall object in front of a
## short one standing beside it, purely because its art reaches further up the
## screen. Feet decide depth, not heads.
static func depth_key(ground: Vector2) -> float:
	return ground.y * depth_px()
