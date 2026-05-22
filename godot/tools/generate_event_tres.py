#!/usr/bin/env python3
"""Generate Godot EventData .tres files from authored event dicts below.

Events are authored as plain Python dicts (much easier to edit than
.tres) and emitted to godot/data/events/. Re-run after editing the
EVENTS list to regenerate.
"""
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "data", "events")


# Each event:
# - id (StringName slug)
# - name (display)
# - prompt (multi-line allowed)
# - choices: each a dict matching the JS schema:
#     stat_check: { id, text, type=stat_check, stat,
#                   outcomes: { crit_good, good, bad, crit_bad } }
#     simple:     { id, text, type=simple, outcome: {...} }
#
# Each outcome:
#   { description, effects: [ {type, value, ...} ] }
#
# Effect types supported by EventModal at event-time:
#   heal, lose_hp, gain_gold, lose_gold, combat_status

EVENTS = [
    {
        "id": "wandering_sage",
        "name": "A Wandering Sage",
        "prompt": ("A robed traveller sits cross-legged in your path, muttering "
                   "to no one in particular. He looks up with sharp, knowing eyes. "
                   "\"A coin for wisdom,\" he says. \"Or wisdom for a coin. The "
                   "order matters.\""),
        "choices": [
            {"id": "listen", "text": "Listen carefully to his words", "type": "stat_check", "stat": "intelligence",
             "outcomes": {
                 "crit_good": {"description": "His riddle clicks into place mid-speech. He laughs and tosses you a coin pouch.",
                               "effects": [{"type": "heal", "value": 4}, {"type": "gain_gold", "value": 8}]},
                 "good":      {"description": "His words are dense, but you catch enough to feel grounded.",
                               "effects": [{"type": "heal", "value": 4}]},
                 "bad":       {"description": "You nod along but understand nothing. He sighs and continues past you.",
                               "effects": []},
                 "crit_bad":  {"description": "He sees through your nodding. A sharp tap to your forehead leaves you reeling.",
                               "effects": [{"type": "lose_hp", "value": 3}]},
             }},
            {"id": "mock", "text": "Mock his rambling", "type": "simple",
             "outcome": {"description": "The sage's smile thins. A crack of light, and you stagger back, bruised.",
                         "effects": [{"type": "lose_hp", "value": 3}]}},
            {"id": "leave", "text": "Walk past in silence", "type": "simple",
             "outcome": {"description": "He watches you go, saying nothing.", "effects": []}},
        ],
    },
    {
        "id": "cursed_chest",
        "name": "The Cursed Chest",
        "prompt": ("An ornate chest sits in the centre of the chamber, runes "
                   "pulsing faintly along its lid. A sour smell of old magic "
                   "hangs in the air."),
        "choices": [
            {"id": "disarm", "text": "Try to disarm the trap", "type": "stat_check", "stat": "dexterity",
             "outcomes": {
                 "crit_good": {"description": "Your fingers find every hidden wire. The chest yawns open on its own.",
                               "effects": [{"type": "gain_gold", "value": 14}]},
                 "good":      {"description": "The trap clicks harmlessly aside. You pocket what's inside.",
                               "effects": [{"type": "gain_gold", "value": 7}]},
                 "bad":       {"description": "A needle pricks your hand before you yank it back.",
                               "effects": [{"type": "lose_hp", "value": 2}]},
                 "crit_bad":  {"description": "The whole chest hisses open. A spray of green mist makes you reel.",
                               "effects": [{"type": "lose_hp", "value": 5}, {"type": "combat_status", "status": "weak", "stacks": 2}]},
             }},
            {"id": "smash", "text": "Smash it open", "type": "stat_check", "stat": "strength",
             "outcomes": {
                 "crit_good": {"description": "One blow shatters the lid clean. The runes never get a chance to fire.",
                               "effects": [{"type": "gain_gold", "value": 10}]},
                 "good":      {"description": "It takes a few swings, but the chest cracks open.",
                               "effects": [{"type": "gain_gold", "value": 5}]},
                 "bad":       {"description": "Splinters fly back at you. The chest gives up some coin but not freely.",
                               "effects": [{"type": "gain_gold", "value": 3}, {"type": "lose_hp", "value": 2}]},
                 "crit_bad":  {"description": "The runes flare and lash you. You drop the lid, ears ringing.",
                               "effects": [{"type": "lose_hp", "value": 5}, {"type": "combat_status", "status": "vulnerable", "stacks": 2}]},
             }},
            {"id": "leave", "text": "Leave it alone", "type": "simple",
             "outcome": {"description": "Whatever it wants, it can want it without you.", "effects": []}},
        ],
    },
    {
        "id": "bandit_ambush",
        "name": "A Bandit Camp",
        "prompt": ("Smoke rises from a low fire in the gully. Three rough figures "
                   "lounge around it; their weapons are within easy reach. They "
                   "haven't noticed you yet."),
        "choices": [
            {"id": "sneak", "text": "Sneak past them", "type": "stat_check", "stat": "dexterity",
             "outcomes": {
                 "crit_good": {"description": "You ghost past them and even snag a coin pouch from the lookout's belt.",
                               "effects": [{"type": "gain_gold", "value": 6}, {"type": "combat_status", "status": "strength", "stacks": 1}]},
                 "good":      {"description": "You slip by unseen.",
                               "effects": []},
                 "bad":       {"description": "A twig snaps. They spring up and you barely outrun the first arrow.",
                               "effects": [{"type": "combat_status", "status": "weak", "stacks": 2}]},
                 "crit_bad":  {"description": "You blunder straight into the lookout. By the time you break free you are scraped raw.",
                               "effects": [{"type": "lose_hp", "value": 4}, {"type": "combat_status", "status": "vulnerable", "stacks": 2}]},
             }},
            {"id": "charge", "text": "Charge in screaming", "type": "stat_check", "stat": "strength",
             "outcomes": {
                 "crit_good": {"description": "You crash into camp like a thunderclap; they scatter, dropping coin in their hurry.",
                               "effects": [{"type": "gain_gold", "value": 8}]},
                 "good":      {"description": "Your charge breaks their nerve and they flee.",
                               "effects": [{"type": "gain_gold", "value": 3}]},
                 "bad":       {"description": "They are ready for you. You trade blows before pulling away.",
                               "effects": [{"type": "lose_hp", "value": 3}]},
                 "crit_bad":  {"description": "You misjudge the distance and stumble into a thrown spear.",
                               "effects": [{"type": "lose_hp", "value": 6}]},
             }},
            {"id": "loop", "text": "Take the long way around", "type": "simple",
             "outcome": {"description": "The detour costs you time and breath, but no blood.",
                         "effects": [{"type": "lose_hp", "value": 1}]}},
        ],
    },
    {
        "id": "merchant_offer",
        "name": "The Merchant's Cart",
        "prompt": ("A merchant flags you down. \"Friend! A potion. A vial. A SECRET. "
                   "Whatever you need.\" His grin is too wide. His prices, you suspect, "
                   "are negotiable."),
        "choices": [
            {"id": "haggle", "text": "Haggle for a better deal", "type": "stat_check", "stat": "charisma",
             "outcomes": {
                 "crit_good": {"description": "By the end he's PAYING you to take a vial off his hands.",
                               "effects": [{"type": "gain_gold", "value": 15}]},
                 "good":      {"description": "You wear him down. He throws in a small coin to seal the deal.",
                               "effects": [{"type": "gain_gold", "value": 6}]},
                 "bad":       {"description": "He smiles through your offer and changes the subject.",
                               "effects": []},
                 "crit_bad":  {"description": "His smile gets wider. You hand over coin you didn't mean to spend.",
                               "effects": [{"type": "lose_gold", "value": 5}]},
             }},
            {"id": "buy_potion", "text": "Buy a vial at full price (5g)", "type": "simple",
             "outcome": {"description": "He pockets your coin and hands over a vial. It tastes like iron and heals well.",
                         "effects": [{"type": "lose_gold", "value": 5}, {"type": "heal", "value": 10}]}},
            {"id": "walk", "text": "Walk away", "type": "simple",
             "outcome": {"description": "He shouts after you for a while. Then he stops.", "effects": []}},
        ],
    },
    {
        "id": "ancient_altar",
        "name": "An Ancient Altar",
        "prompt": ("Stone steps lead up to a worn altar carved with symbols you "
                   "don't quite know. A faint warmth pulses from the centre. Coin "
                   "marks the dust where others have offered before."),
        "choices": [
            {"id": "decipher", "text": "Try to decipher the inscriptions", "type": "stat_check", "stat": "intelligence",
             "outcomes": {
                 "crit_good": {"description": "The symbols rearrange in your mind. Warm light floods you and a coin tumbles loose.",
                               "effects": [{"type": "heal", "value": 12}, {"type": "gain_gold", "value": 5}]},
                 "good":      {"description": "You read enough to channel the altar's blessing.",
                               "effects": [{"type": "heal", "value": 7}]},
                 "bad":       {"description": "The script slides off your eyes. Nothing happens.",
                               "effects": []},
                 "crit_bad":  {"description": "You mispronounce a single rune. The altar bites back.",
                               "effects": [{"type": "lose_hp", "value": 4}]},
             }},
            {"id": "offer", "text": "Make an offering (10g)", "type": "simple",
             "outcome": {"description": "Your coins ring against the stone. The altar warms in answer.",
                         "effects": [{"type": "lose_gold", "value": 10}, {"type": "heal", "value": 14}]}},
            {"id": "leave", "text": "Step away", "type": "simple",
             "outcome": {"description": "Some things are best left undisturbed.", "effects": []}},
        ],
    },
]


def fmt_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        # escape backslashes and quotes
        esc = v.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{esc}"'
    if isinstance(v, list):
        return "[" + ", ".join(fmt_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{fmt_value(k)}: {fmt_value(val)}" for k, val in v.items()) + "}"
    raise TypeError(f"Unsupported value type {type(v).__name__}: {v!r}")


def emit_tres(event: dict) -> str:
    eid = event["id"]
    prompt = event["prompt"].replace('"', '\\"').replace("\n", "\\n")
    choices_literal = fmt_value(event["choices"])
    return (
        f'[gd_resource type="Resource" script_class="EventData" load_steps=2 format=3 uid="uid://event_{eid}"]\n'
        f'\n'
        f'[ext_resource type="Script" path="res://scripts/resources/EventData.gd" id="1_event"]\n'
        f'\n'
        f'[resource]\n'
        f'script = ExtResource("1_event")\n'
        f'id = &"{eid}"\n'
        f'display_name = "{event["name"]}"\n'
        f'prompt = "{prompt}"\n'
        f'choices = {choices_literal}\n'
        f'difficulty_tags = PackedStringArray()\n'
        f'run_limit = 0\n'
        f'source_game = ""\n'
        f'rarity = "Common"\n'
        f'tags = PackedStringArray()\n'
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for e in EVENTS:
        path = os.path.join(OUT_DIR, f"{e['id']}.tres")
        with open(path, "w") as f:
            f.write(emit_tres(e))
        print(f"Wrote {path}")


if __name__ == "__main__":
    main()
