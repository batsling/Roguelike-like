class_name ReferenceCatalog

# AUTO-GENERATED from tools/Roguelikes.xlsx (statusesnew + addonsnew sheets)
# by scripts/import-reference-godot.py. Do not edit by hand — re-run the
# importer instead. Drives the Collection screen's Reference tab; the set
# here matches the statuses/addons actually wired into the Godot build.

const STATUSES: Array = [
	{ "name": "Arcane", "description": "Raise or Lower the Magic damage dealt by this target by X", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Uncommon", "icon": "Arcane" },
	{ "name": "Power", "description": "Raise or Lower the Melee or Ranged damage dealth by this target by X", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Uncommon", "icon": "Power" },
	{ "name": "Vulnerable", "description": "All damage deals 50% more to target", "type": "Debuff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Vulnerable" },
	{ "name": "Defense", "description": "Raise or Lower the Block gained by this target by X", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Uncommon", "icon": "Defense" },
	{ "name": "Persistence", "description": "Raise or Lower the severity of all non-basic statuses gained or inclifted in combat by X if possible", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Rare", "icon": "Persistence" },
	{ "name": "Blind", "description": "Each hit from an Attack have a 30% Miss Chance", "type": "Debuff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Blind" },
	{ "name": "Weak", "description": "Target deals 25% less damage.", "type": "Debuff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Weak" },
	{ "name": "Frail", "description": "Block gained from Cards is reduced by 25%", "type": "Debuff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Frail" },
	{ "name": "Dodge", "description": "Negate the next X sources of damage where X is the stack", "type": "Buff", "stackable": true, "decay": "When the target would take damage", "who": "All", "preference": "Positive", "rarity": "Rare", "icon": "Dodge" },
	{ "name": "Burn", "description": "Deals 3 damage to target at the end of turn", "type": "Debuff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Burn" },
	{ "name": "Poison", "description": "Deals X damage to any target where X is the stack at the start of turn", "type": "Debuff", "stackable": true, "decay": "Down by 1 at start of turn", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Poison" },
	{ "name": "Regeneration", "description": "At the end of target's turn, it gains X health where X is the stack", "type": "Buff", "stackable": true, "decay": "Down by 1 at end of turn", "who": "All", "preference": "Positive", "rarity": "Uncommon", "icon": "Regeneration" },
	{ "name": "Bleed Thorns", "description": "When a target with Bleed Thorns gets dealt Melee Dmg, the target Inflicts X Bleed to the attacker/recipient", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Rare", "icon": "BleedThorns" },
	{ "name": "Bleed", "description": "Target loses 1 Health per stack at the end of their turn.", "type": "Debuff", "stackable": true, "decay": "UP by 1 at the end of turn", "who": "All", "preference": "Negative", "rarity": "Uncommon", "icon": "Bleed" },
	{ "name": "Thorns", "description": "When a target with Thorns gets dealt Melee Dmg, the target deals X Dmg to the attacker/recipient", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Uncommon", "icon": "Thorns" },
	{ "name": "Soul Link", "description": "Whenever a soul linked target loses health, all soul linked characters lose that health as well.", "type": "Debuff", "stackable": false, "decay": "None", "who": "All", "preference": "Negative", "rarity": "Rare", "icon": "SoulLink" },
	{ "name": "Buffer", "description": "Prevent the next X times the target would lose Health", "type": "Buff", "stackable": true, "decay": "Down when player was going to lose health", "who": "All", "preference": "Positive", "rarity": "Rare", "icon": "Buffer" },
	{ "name": "Crit Chance Up", "description": "Chance for a hit on an enemy to become a Critical Hit dealing Critical Damage, which starts at 100%.", "type": "Buff", "stackable": true, "decay": "None", "who": "All", "preference": "Positive", "rarity": "Common", "icon": "CritChanceUp" },
	{ "name": "Bruise", "description": "Increases all non-magic melee and ranged damage taken by 1 per stack.", "type": "Debuff", "stackable": true, "decay": "None", "who": "All", "preference": "Negative", "rarity": "Common", "icon": "Bruise" },
	{ "name": "Fear", "description": "Your non-Skill Cards cost 1 more Energy, lose 1 Fear whenever you play a Skill Card", "type": "Debuff", "stackable": true, "decay": "Down by 1 on played Skill Card", "who": "Player", "preference": "Negative", "rarity": "Uncommon", "icon": "Fear" },
]

const ADDONS: Array = [
	{ "name": "Cleave", "deckbuilder": "Applies this to target and every target on it's side (Allies or Enemies)", "action": "Radius is a full circle around the player", "strategy": "The attacks radius is all around the player", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Melee", "deckbuilder": "Triggers effects from contact", "action": "Attack is a melee hit with a set range", "strategy": "Attack is a melee hit with a set range", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Ranged", "deckbuilder": "Ignores effects come from contact", "action": "Attack is a projectile", "strategy": "Attack is a projectile", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Ethereal", "deckbuilder": "If an Ethereal card is in your hand at the end of your turn, it is Exhausted.", "action": "Cooldown time is doubled", "strategy": "If you don't use an Etheral Ability every turn, all Ethereal Abilities will be deactivated for the rest of the combat", "has_value": false, "attaches_to": "Cards", "forms": "" },
	{ "name": "Exhaust", "deckbuilder": "Put the card in the Exhaust Pile", "action": "This Ability can only be used once per combat", "strategy": "This Ability can only be used once per combat", "has_value": false, "attaches_to": "Cards", "forms": "" },
	{ "name": "Innate", "deckbuilder": "Place this card on the top of your deck at the start of combat", "action": "Card is immediately played at the start of combat", "strategy": "the player can play 1 Innate ability for free at the start of combat", "has_value": false, "attaches_to": "Cards", "forms": "" },
	{ "name": "Fishing Weight", "deckbuilder": "Gain +1 Dmg for every 3 Common, 2 Uncommon, or 1 Rare fish in your loot inventory", "action": "Gain +1 Dmg for every 3 Common, 2 Uncommon, or 1 Rare fish in your loot inventory", "strategy": "Gain +1 Dmg for every 3 Common, 2 Uncommon, or 1 Rare fish in your loot inventory", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Infuse", "deckbuilder": "If this kills an enemy, gain X Max Health", "action": "If this kills an enemy, 10% chance to gain X Max Health", "strategy": "If this kills an enemy, gain X Max Health", "has_value": true, "attaches_to": "All", "forms": "" },
	{ "name": "Wealth", "deckbuilder": "Add +1 for every 10 Gold the player has", "action": "Add +1 for every 10 Gold the player has", "strategy": "Add +1 for every 10 Gold the player has", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Indiscriminate", "deckbuilder": "Will use random applicable targets", "action": "Will use random applicable targets in an area", "strategy": "Will use random applicable targets in an area", "has_value": false, "attaches_to": "All", "forms": "" },
	{ "name": "Replay", "deckbuilder": "This card gets played again X times", "action": "This card gets played again X times", "strategy": "This ability gets played again X times", "has_value": true, "attaches_to": "Cards", "forms": "" },
	{ "name": "Unplayable", "deckbuilder": "This card cannot be played", "action": "Cooldown time is doubled", "strategy": "If the player has an Unplayable card, at least one Unplayable card must be equipped", "has_value": false, "attaches_to": "Cards", "forms": "" },
	{ "name": "Eternal", "deckbuilder": "This card cannot be removed", "action": "This card cannot be removed", "strategy": "This card cannot be removed", "has_value": false, "attaches_to": "Cards", "forms": "" },
]
