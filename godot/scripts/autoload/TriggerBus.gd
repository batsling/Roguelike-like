extends Node

# Global signal hub for item / card / event triggers.
# Items declare {on: "combat_start", effects: [...]} and the system
# connects them to the matching signal at acquisition time.
#
# The combat scene (and overworld, event modal, etc.) emit these signals
# at the appropriate moments. Most signals carry a context Dictionary so
# handlers can inspect/modify what's happening.

# --- Combat lifecycle ---
# All signals on this bus are declared here but emitted from other
# scripts (combat scene, overworld, event modal, etc.). Godot flags
# them as unused locally, hence the warning block.
@warning_ignore_start("unused_signal")
signal combat_started(ctx: Dictionary)
signal combat_ended(ctx: Dictionary)        # ctx.victory: bool

# --- Turn lifecycle ---
signal turn_started(ctx: Dictionary)        # ctx.turn: int
signal turn_ended(ctx: Dictionary)

# --- Card events ---
signal card_drawn(ctx: Dictionary)          # ctx.card
signal card_played(ctx: Dictionary)         # ctx.card, ctx.target
signal card_exhausted(ctx: Dictionary)
signal card_discarded(ctx: Dictionary)

# --- Damage events ---
signal damage_dealt(ctx: Dictionary)        # ctx.source, ctx.target, ctx.amount
signal damage_taken(ctx: Dictionary)        # ctx.target, ctx.attacker, ctx.amount
signal enemy_killed(ctx: Dictionary)        # ctx.enemy
signal enemy_spawned(ctx: Dictionary)       # ctx.enemy — fired from CombatActor.from_enemy
                                            # after item modifiers (Alien Baby et al) apply

# --- Status events ---
signal status_applied(ctx: Dictionary)      # ctx.target, ctx.status, ctx.stacks
signal status_removed(ctx: Dictionary)

# --- Run lifecycle ---
signal game_beaten(ctx: Dictionary)         # ctx.game_id
signal floor_entered(ctx: Dictionary)       # ctx.game_id
signal item_acquired(ctx: Dictionary)       # ctx.item
signal item_lost(ctx: Dictionary)
signal item_used(ctx: Dictionary)           # ctx.item — a USABLE consumable was activated
signal curse_applied(ctx: Dictionary)
signal curse_removed(ctx: Dictionary)
@warning_ignore_restore("unused_signal")
