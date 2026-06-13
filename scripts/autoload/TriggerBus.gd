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
signal turn_started(ctx: Dictionary)        # ctx.turn: int — a discrete turn /
                                            # combat ROOM begins. Drives "on the
                                            # Nth turn" one-shots (Horn Cleat,
                                            # if_turn). Room-based in Action.
signal turn_tick(ctx: Dictionary)           # the recurring "a turn elapsed"
                                            # heartbeat. Fires once per turn in
                                            # deckbuilder/strategy and on the
                                            # real-time turn-tick timer in Action.
                                            # Drives recurring per-turn effects
                                            # (Happy Flower; the per-turn attack
                                            # window for Ornamental Fan / Shuriken).
signal turn_ended(ctx: Dictionary)

# --- Card events ---
signal card_drawn(ctx: Dictionary)          # ctx.card
signal card_played(ctx: Dictionary)         # ctx.card, ctx.target — fires BEFORE the
                                            # card's own effects resolve
signal card_resolved(ctx: Dictionary)       # ctx.card, ctx.target — fires AFTER the
                                            # card's effects land, before discard/exhaust.
                                            # Duplicator listens here to replay weapon
                                            # attacks so the extra hit follows the first.
signal card_exhausted(ctx: Dictionary)
signal card_discarded(ctx: Dictionary)

# --- Damage events ---
signal damage_dealt(ctx: Dictionary)        # ctx.source, ctx.target, ctx.amount
signal damage_taken(ctx: Dictionary)        # ctx.target, ctx.attacker, ctx.amount
signal attack_landed(ctx: Dictionary)       # ctx.source, ctx.target — a melee/ranged
                                            # attack connected (block counts, miss/dodge
                                            # don't). Dead Eye's streak grows here.
signal attack_missed(ctx: Dictionary)       # ctx.source, ctx.target — a melee/ranged
                                            # attack whiffed (Blind). Dead Eye resets here.
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
signal curse_applied(ctx: Dictionary)        # ctx.curse — a curse was added to
                                            # active_curses (Vitality Orb).
signal curse_removed(ctx: Dictionary)        # ctx.curse — a curse left
                                            # active_curses (Golden Beetle).
signal curse_card_removed(ctx: Dictionary)   # ctx.card — a CURSE-type card left
                                            # the deck (Golden Beetle). Distinct
                                            # from curse_removed: a curse and a
                                            # curse CARD are separate things —
                                            # Death/Du-Vu/Vitality count curses
                                            # only, Golden Beetle counts both.
signal chest_granted(ctx: Dictionary)        # ctx.count — N item-reward "chests"
                                            # were granted (Golden Beetle). The
                                            # overworld redeems pending chests
                                            # into item-choice reward screens.
@warning_ignore_restore("unused_signal")
