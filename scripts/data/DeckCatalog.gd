class_name DeckCatalog

# The run-wide deck choice, ported from the HTML build's AVAILABLE_DECKS
# (legacy-web/js/constants.js). A deck is NOT a starting card list — the
# character still supplies the opening deck and items. Picking a deck only
# narrows which cards appear as combat/shop card rewards during the run:
# `tag_filter` feeds Data.reward_card_pool (empty = the full pool, i.e. the
# "Random" deck). Level-up card rewards stay character-scoped
# (CharacterData.level_up_card_tag), matching the HTML behaviour.
#
# Deck wins per character are tracked in GameStats.record_deck_win and shown
# as the "Beaten With Deck" checklist on the character select + Collection.

const DEFAULT_DECK_ID := &"Random"

const DECKS: Array = [
	{
		"id": &"Random",
		"name": "Random",
		"description": "Cards from any pool may appear as rewards.",
		"tag_filter": &"",
		"image": "",
	},
	{
		"id": &"Ironclad",
		"name": "Ironclad",
		"description": "Only Ironclad cards appear in card rewards and shops.",
		"tag_filter": &"ironclad",
		"image": "res://images/decks/IroncladDeck.png",
	},
	{
		"id": &"Silent",
		"name": "Silent",
		"description": "Only Silent cards appear in card rewards and shops.",
		"tag_filter": &"silent",
		"image": "res://images/decks/SilentDeck.png",
	},
]

static func all() -> Array:
	return DECKS

static func get_deck(id: StringName) -> Dictionary:
	for d in DECKS:
		if d["id"] == id:
			return d
	return {}

# The reward-pool tag for a deck id (&"" = unfiltered). Unknown ids fall back
# to the Random deck's empty filter so a stale save can never brick rewards.
static func tag_filter(id: StringName) -> StringName:
	var d := get_deck(id)
	return d.get("tag_filter", &"") if not d.is_empty() else &""

static func display_name(id: StringName) -> String:
	var d := get_deck(id)
	return String(d.get("name", String(id))) if not d.is_empty() else String(id)

# Deck art, or null for decks without an image (Random shows a placeholder).
static func image(id: StringName) -> Texture2D:
	var d := get_deck(id)
	var path := String(d.get("image", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)
