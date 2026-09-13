//
//  Board.swift
//  Foretold
//

/// A tile coordinate on the board. Origin (0, 0) is the bottom-left tile.
struct GridPosition: Hashable {
    var x: Int
    var y: Int
}

extension GridPosition {
    /// Manhattan distance: tiles apart moving only orthogonally.
    func distance(to other: GridPosition) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }
}

/// The eight directions an attack can face. Orthogonal patterns are authored
/// facing right (+x); diagonal patterns are authored facing up-right (+x, +y).
/// Both are rotated in quarter turns to the other three facings of their kind.
enum Direction: CaseIterable {
    case right, up, left, down
    case upRight, upLeft, downLeft, downRight

    var isDiagonal: Bool {
        switch self {
        case .right, .up, .left, .down: return false
        case .upRight, .upLeft, .downLeft, .downRight: return true
        }
    }

    /// Quarter turns from this direction's canonical facing (right for
    /// orthogonal, up-right for diagonal).
    private var quarterTurns: Int {
        switch self {
        case .right, .upRight: return 0
        case .up, .upLeft: return 1
        case .left, .downLeft: return 2
        case .down, .downRight: return 3
        }
    }

    /// Rotates a canonically-authored offset into this direction.
    func rotated(_ offset: GridPosition) -> GridPosition {
        var result = offset
        for _ in 0..<quarterTurns {
            result = GridPosition(x: -result.y, y: result.x)
        }
        return result
    }

    /// One tile of travel along this direction (diagonal steps move both axes).
    var unitStep: GridPosition {
        isDiagonal ? rotated(GridPosition(x: 1, y: 1)) : rotated(GridPosition(x: 1, y: 0))
    }

    /// Compass glyph for HUD readouts.
    var arrow: String {
        switch self {
        case .right: return "→"
        case .up: return "↑"
        case .left: return "←"
        case .down: return "↓"
        case .upRight: return "↗"
        case .upLeft: return "↖"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
    }

    /// The direction that best matches aiming from origin toward tile; diagonal
    /// facings are only chosen when allowed and the aim is closer to 45° than to
    /// an axis. Nil when origin and tile coincide.
    static func aiming(from origin: GridPosition, toward tile: GridPosition, allowDiagonals: Bool) -> Direction? {
        let dx = tile.x - origin.x
        let dy = tile.y - origin.y
        guard dx != 0 || dy != 0 else { return nil }
        if allowDiagonals && min(abs(dx), abs(dy)) * 2 > max(abs(dx), abs(dy)) {
            switch (dx > 0, dy > 0) {
            case (true, true): return .upRight
            case (false, true): return .upLeft
            case (false, false): return .downLeft
            case (true, false): return .downRight
            }
        }
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .up : .down
    }
}

/// Scenery on the board. Walls block movement and stop attacks dead; barrels
/// block movement and explode when any attack sweeps them, damaging everything
/// beside them (player, enemies, and other barrels — chain reactions included).
struct Obstacle {
    enum Kind {
        case wall, barrel
    }

    /// Barrel flavors: `standard` (orange, full blast), `fire` (green — no blast
    /// damage, leaves burning ground instead), `weak` (yellow, half blast — what
    /// the Keg lobs).
    enum BarrelKind {
        case standard, fire, weak
    }

    let id: Int
    let kind: Kind
    /// Walls are fixed, but barrels can be shoved (a knockback swing) or reeled
    /// (a grapple) to a new tile, so this is mutable.
    var position: GridPosition
    /// Barrels the boss lobbed in with its barrage — drawn red, and the tiles
    /// it prefers to set off with a later detonate intent.
    var volatile = false
    /// The barrel's flavor (ignored for walls).
    var barrelKind: BarrelKind = .standard
    /// A wall that crumbles when struck or caught in a blast, instead of standing
    /// forever (ignored for barrels).
    var destructible = false
}

/// A floor trap that toggles each turn: while `active`, anyone ending the turn
/// standing on it takes a bite. Non-blocking — you (and enemies) walk right over.
struct SpikeTrap {
    let position: GridPosition
    /// True on the turns it will bite; flips every turn after the bite resolves.
    var active: Bool
}

/// A linked pair of floor tiles: stepping onto either end warps the mover to the
/// other (if that tile is free). Non-blocking.
struct Teleporter {
    let id: Int
    let a: GridPosition
    let b: GridPosition

    /// The far end of the pair for a tile on it, or nil if `tile` isn't an end.
    func exit(from tile: GridPosition) -> GridPosition? {
        if tile == a { return b }
        if tile == b { return a }
        return nil
    }
}

/// A patch of floor that changes how a mover crosses it — non-blocking, and
/// (unlike spikes) harmless on its own. `ice` grants +1 move and, when a move
/// ends on it, slides the mover on along their travel until the ice runs out or
/// something stops them; `mud` costs a tile of movement while stood on. Applies
/// to the player and enemies alike (symmetry), folded into enemy drafts so their
/// telegraph still shows where they truly end up.
struct TerrainPatch {
    enum Kind {
        case ice, mud
    }

    let position: GridPosition
    let kind: Kind
}

/// A weapon lying on the ground. While standing on one the player may draft a
/// pickup, spending their attack (and dodge) for the turn to swap it with the
/// equipped weapon — the old weapon stays on the tile for trading back later.
struct WeaponDrop {
    let id: Int
    let weapon: Weapon
    let position: GridPosition
    /// Dropped by a slain elite: survives level regeneration, never expires,
    /// and doesn't count toward the floor-weapon cap.
    var isBossDrop = false
}
