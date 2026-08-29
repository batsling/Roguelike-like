class_name HowToPlayText
extends RefCounted

# The written manual — every word of it, as data. `HowToPlayScreen` draws this
# and knows nothing about what it says; this file says it and knows nothing
# about how it looks.
#
# WHY IT IS WRITTEN LIKE THIS
#
# The research on written instruction (Carroll's minimalist / "minimal manual"
# work, and the same advice that turns up in every tutorial-design piece) lands
# on four things, and this manual is shaped by them:
#
#   1. TASK ORDER, NOT SYSTEM ORDER. Chapters run in the order a player meets
#      the thing, not in the order the spec documents it. Chapter 1 is one whole
#      run from the menu to the win, because a player's first question is never
#      "what is a status" — it is "what do I do".
#   2. WHAT, THEN HOW, THEN WHY. Every mechanic gets named, then operated, then
#      justified. The justification goes LAST and is skippable; the operation
#      never is.
#   3. MODULAR AND SELF-CONTAINED. Each chapter is a page you can open on its own
#      without having read the one before it. This costs some repetition and is
#      worth it: nobody reads a manual front to back, they open it at the bit
#      they are stuck on.
#   4. ERROR RECOGNITION AND RECOVERY IS ITS OWN CHAPTER. "When it goes wrong"
#      (§11) exists because minimalist instruction is explicit that documenting
#      the recovery path matters more than documenting the happy path — the happy
#      path is the one people can work out for themselves.
#
# The one deliberate departure: text is doing more work here than a tutorial
# would normally give it. That is the right call for THIS game — the mechanics
# are strategy-game mechanics (a routing puzzle over a graph, a pressure ladder,
# a stack that compounds) and those are the ones players cannot reverse-engineer
# from watching. The parts of the game that ARE self-teaching — click a card, it
# opens; press Report, it asks — are given a line each and no more.
#
# NUMBERS COME FROM THE CODE. Every figure below is read off the constant that
# actually governs it, so a balance change cannot leave the manual quietly lying.
# If you are about to type a number in here, find the constant instead.

# --- block kinds the screen knows how to draw ------------------------------
#
#   {"k": "p",    "t": "..."}                    a paragraph
#   {"k": "b",    "t": "..."}                    a bullet
#   {"k": "h",    "t": "..."}                    a sub-heading inside a chapter
#   {"k": "kv",   "t": "term", "v": "meaning"}   a definition row
#   {"k": "note", "t": "..."}                    a called-out aside
#   {"k": "step", "t": "...", "n": 1}            a numbered step
#   {"k": "row",  "c": ["a", "b"], "head": bool} a table row

static func _p(t: String) -> Dictionary: return {"k": "p", "t": t}
static func _b(t: String) -> Dictionary: return {"k": "b", "t": t}
static func _h(t: String) -> Dictionary: return {"k": "h", "t": t}
static func _kv(t: String, v: String) -> Dictionary: return {"k": "kv", "t": t, "v": v}
static func _note(t: String) -> Dictionary: return {"k": "note", "t": t}
static func _step(n: int, t: String) -> Dictionary: return {"k": "step", "n": n, "t": t}
static func _row(c: Array, head: bool = false) -> Dictionary:
	return {"k": "row", "c": c, "head": head}


# Every chapter, in reading order. Each is
# {id, title, icon, blurb, blocks} — `blurb` is the one line the main menu's
# contents panel shows under the title.
static func chapters() -> Array:
	return [
		_ch_start(), _ch_choosing(), _ch_playing(), _ch_enemies(), _ch_board(),
		_ch_health(), _ch_verbs(), _ch_gold(), _ch_events(), _ch_pack(),
		_ch_bosses(), _ch_wrong(), _ch_screen(),
	]


# ---------------------------------------------------------------------------
# 1. Start here
# ---------------------------------------------------------------------------

static func _ch_start() -> Dictionary:
	return {
		"id": &"start", "icon": "▶", "title": "Start here",
		"blurb": "The whole game in one page.",
		"blocks": [
			_p("The dungeon is your backlog. Every room on the map is a real "
				+ "roguelike that really exists, and the way you fight through a "
				+ "room is to go away, open that game, and play it. This app is "
				+ "the Dungeon Master: it decides what you have to do in there, "
				+ "and it takes your word for whether you did it."),
			_p("There is no combat here to play. The combat is Hades."),
			_h("One run, start to finish"),
			_step(1, "Pick a character. That sets your Health and the charges you "
				+ "start with."),
			_step(2, "Pick where you start. You are offered three games, and the "
				+ "one you take is the run's first game — not a free move. The "
				+ "Amulet is named on this panel, and every card says how many "
				+ "games away it is, so you are choosing a road knowing where it "
				+ "ends."),
			_step(3, "The game you took has an ENEMY standing on it, and that "
				+ "enemy is a GOAL: something to do inside the real game. Beat a "
				+ "boss without healing. Descend ten floors. Win in one deck cycle. "
				+ "An ESCORT spawns beside it — a second enemy, with a second goal, "
				+ "that beating the game does not answer for."),
			_step(4, "Go and play it. Actually play it — this is the part that "
				+ "takes an evening, and it is the whole point."),
			_step(5, "Come back and press Completed Game, and tick whichever "
				+ "goals you actually did on the way. Nobody is checking. That is "
				+ "the honour system and it is load-bearing."),
			_step(6, "A goal you ticked: that enemy dies, drops a piece of loot on "
				+ "the board, pays a gold, and makes the chest waiting on the "
				+ "reward screen bigger. One you left unticked: it survives, "
				+ "follows you, and starts hitting you after every game you play "
				+ "from now on."),
			_step(7, "You are offered a new set of games, connected to where you "
				+ "stand. Choose one. Go to 3."),
			_p("The run ends when you reach and clear the AMULET game — that is "
				+ "the win — or when your Health hits zero."),
			_h("What makes it a game rather than a list"),
			_p("Three things, and they are the three chapters after this one."),
			_b("The map is the real influence graph of the genre. Rogue connects "
				+ "to NetHack connects to Spelunky. You can only travel along "
				+ "edges that are actually there, so where you can go next is "
				+ "decided by what you just played."),
			_b("Enemies you did not beat do not go away. They pile up and they "
				+ "all hit you, every game, forever, until you go back and finish "
				+ "their goals. A run does not kill you; a backlog does."),
			_b("The closer you get to the Amulet, the faster everything chasing "
				+ "you moves. Rushing the win and taking the long way are both "
				+ "real strategies, and which one is right depends on what is on "
				+ "your tail."),
			_note("You never have to finish a game in one sitting, and the app "
				+ "does not care how long you take. Save the run and close it. It "
				+ "will be here when the game is."),
		],
	}


# ---------------------------------------------------------------------------
# 2. Choosing where to go
# ---------------------------------------------------------------------------

static func _ch_choosing() -> Dictionary:
	return {
		"id": &"choosing", "icon": "🗺", "title": "Choosing where to go",
		"blurb": "The offering, the card, and the route to the Amulet.",
		"blocks": [
			_p("After every game you are shown an OFFERING: a few cover cards, "
				+ "drawn from the games connected to the one you are standing on. "
				+ "This is the only decision the app actually asks you to make, so "
				+ "it is the one with everything behind it."),
			_h("Click the card, do not just take it"),
			_p("Clicking a card OPENS it rather than travelling to it. The card "
				+ "itself is only the cover, the name, and a flag if it is the "
				+ "Amulet or a shop. Everything you need is inside."),
			_kv("The route", "The optimal path from that game to the Amulet, drawn "
				+ "as the real ladder — so you can see what taking this card does "
				+ "to the road, not just where it puts you."),
			_kv("The enemy", "Who is waiting there, and the exact goal you would "
				+ "be playing for, written out with any clauses your own statuses "
				+ "add to it — plus a warning when an escort spawns with it, which "
				+ "is every card that is not a boss."),
			_kv("The shields", "How many Temporary Shields that game hands you — "
				+ "one hit stopped each. See §3."),
			_kv("The pace", "What taking it does to how fast the board moves — "
				+ "speeds up, slows down, or no change."),
			_kv("Connections", "How many games it opens onto, how many of those "
				+ "still owe you an event, and how many are shops."),
			_kv("Your record", "Whether you have beaten it before, in this run and "
				+ "in your life."),
			_h("The route badge"),
			_kv("★ OPTIMAL — N steps left", "This card is on a shortest path to "
				+ "the Amulet. Taking it spends a game and buys a step."),
			_kv("↩ Detour +N", "This card is off the shortest path. It costs you N "
				+ "extra games to come back from."),
			_kv("🏆 THE AMULET", "This is the game the run is a search for. Beat "
				+ "its goal and the run is won, on the spot."),
			_h("Pressure: why the long way is a real option"),
			_p("Handing a game in does not move the board. Out in the wilds you can "
				+ "play a game, report it and walk away with the stack exactly where "
				+ "you left it — what moves them is the runs you LOSE, one turn "
				+ "each. What closing on the Amulet buys them is EXTRA TURNS at the "
				+ "end of every game you report:"),
			_row(["Hops to the Amulet", "Extra turns", "Band"], true),
			_row(["%d or more" % RunDifficulty.FAR_HOPS,
				"%d" % RunDifficulty.EXTRA_FAR, "Distant"]),
			_row(["%d – %d" % [RunDifficulty.MID_HOPS, RunDifficulty.FAR_HOPS - 1],
				"%d" % RunDifficulty.EXTRA_MID, "Closing"]),
			_row(["%d or fewer" % (RunDifficulty.MID_HOPS - 1),
				"%d" % RunDifficulty.EXTRA_NEAR, "Doorstep"]),
			_p("A turn is one action for every enemy on the board: anything in "
				+ "your face swings, everything behind it steps a column closer. "
				+ "So on the Amulet's doorstep finishing a game is two free swings "
				+ "from every follower you left alive, and an enemy two columns back "
				+ "is not safe any more — it can walk into range and hit you before "
				+ "you have chosen the next card."),
			_p("This is the whole reason routing is a decision. Every step toward "
				+ "the Amulet used to be strictly good. Now: route wide and the "
				+ "board only moves when you fail; run at the Amulet and it moves "
				+ "every time you finish anything. Neither is correct in general. "
				+ "What decides it is how many followers you are dragging — three "
				+ "of them at 2 extra turns is a very different sum from three at "
				+ "none."),
			_note("Taking the Amulet card itself carries no pace warning. There is "
				+ "no next game for the enemies to act in — you have either won or "
				+ "you have not."),
		],
	}


# ---------------------------------------------------------------------------
# 3. Playing the game
# ---------------------------------------------------------------------------

static func _ch_playing() -> Dictionary:
	return {
		"id": &"playing", "icon": "🎮", "title": "Playing the game",
		"blurb": "Shields, lost runs, the checklist, and getting out.",
		"blocks": [
			_p("You have chosen a game. The app now does nothing until you come "
				+ "back — go and play. What follows is what the screen is for "
				+ "while you are away and when you return."),
			_h("Shields are hits you do not take"),
			_p("A SHIELD stops ONE INSTANCE of damage — the whole of it, however "
				+ "big. A 3-damage swing breaks one shield and lands for nothing; so "
				+ "does a 1-damage one. They are drawn as pips over your character."),
			_p("There are two kinds, and the only difference is whether they "
				+ "survive the game:"),
			_kv("%ss" % GameState.TEMP_SHIELD_NAME,
				"What selecting a game hands you. They EXPIRE when you report it — "
				+ "they are that game's armour and nobody else's."),
			_kv("%ss" % GameState.SHIELD_NAME,
				"Gained off the board (a pill, a relic). They STAY until something "
				+ "breaks one, so they are worth carrying toward a game you expect "
				+ "to hurt."),
			_kv("Any game grants", "%d %ss" % [GameLoop2.SHIELDS_PER_GAME,
				GameState.TEMP_SHIELD_NAME]),
			_kv("A Traditional roguelike", "%d — the long haul gets more"
				% GameLoop2.SHIELDS_TRADITIONAL),
			_p("A hit breaks a Temporary Shield first, every time. They are the "
				+ "ones about to expire anyway, so spending the pool that survives "
				+ "while one of them is still standing would be the wrong way round."),
			_h("Losing a run gives the enemies a turn"),
			_p("A roguelike is not beaten in one sitting, and you will lose runs of "
				+ "it. Every time you do, you tick the attempt tracker yourself, "
				+ "and each tick hands the enemies A TURN: the front line swings "
				+ "and everything behind it walks a column closer, exactly as it "
				+ "does when you report a game."),
			_p("It costs you no shields of either kind. There is no limit on how "
				+ "many times you may fail at a game — what there is, is a board "
				+ "that is one turn closer every time you do, and a pool that is "
				+ "one shield smaller each time a swing gets through."),
			_p("So a game you clear first try never lets the stack move at all. A "
				+ "game that fights back walks it into your face and then makes you "
				+ "report from there. That is the tension the whole run is built "
				+ "on: your Health is only ever in danger when you are already "
				+ "having a bad time."),
			_note("There is no undo on the tracker. A tick hands the enemies a "
				+ "turn and the turn stands — press it when you have actually "
				+ "lost a run, not to see what happens.")
			,
			_h("The checklist"),
			_p("The left column is everything you are trying to do inside the real "
				+ "game, in one list:"),
			_b("This game's enemy and its goal."),
			_b("Every follower's outstanding goal — old goals can be cleared at "
				+ "any time, in any game, and doing so kills that follower exactly "
				+ "as if you had beaten it on time."),
			_b("Your character's level-up challenge, which is a fresh chance every "
				+ "single game."),
			_b("Any standing objectives your statuses have added."),
			_p("Hover a row and the body it belongs to lights up on the board. "
				+ "Hover a body and its row lights up. They are the same fact "
				+ "written twice."),
			_h("A tick happens NOW"),
			_p("Tick a row the moment you do the thing. It asks you to confirm, "
				+ "and then it RESOLVES — mid-game, while you are still playing. "
				+ "The enemy dies and drops its loot onto the board. The reward "
				+ "is paid. The level is taken."),
			_p("You do not have to finish the game first, and losing runs does "
				+ "not stop you: a goal you cleared in the first hour is worth "
				+ "something for the rest of the evening rather than sitting there "
				+ "waiting for you to press a button."),
			_note("There are no take-backs. The confirm is the safeguard — an "
				+ "enemy that is already dead cannot be un-killed."),
			_h("Reporting"),
			_p("Press Completed Game when you are done with the game — done, not "
				+ "necessarily victorious. Two different things are being claimed, "
				+ "and they are claimed separately:"),
			_kv("The button", "Says you played and finished the real game. That is "
				+ "what counts it as beaten, pays the return-trip Dash, and wins "
				+ "the run at the Amulet."),
			_kv("The tick boxes", "One per enemy on the board — including whatever "
				+ "walked on when you took this game. Ticking one says you did that "
				+ "enemy's goal, and doing that is what kills it. They are answered "
				+ "as you go, though, so by the time you press the button they are "
				+ "usually all settled."),
			_p("So you can finish a game and leave everything on the board still "
				+ "following you, or clear three old goals during a game you never "
				+ "finished. Neither is a failure state; an unticked enemy is a "
				+ "debt."),
			_note("Nothing on the board belongs to the game you are playing. What "
				+ "walked on with it is a follower like every other body from the "
				+ "moment it lands — you can bomb it, push it, or leave its goal "
				+ "for three games and clear it later."),
			_h("Escaping"),
			_p("If a game is going nowhere you can leave it — ONCE IT HAS DRAWN "
				+ "BLOOD. Escape is offered the moment an enemy's attack takes "
				+ "Health off you during this game, and immediately if this run has "
				+ "already beaten that game before. Putting THREE enemies down on "
				+ "the game you are playing opens it too — that is a price you can "
				+ "pay on purpose rather than one the board has to hand you."),
			_p("So the way out arrives when the board proves it is the problem: "
				+ "lose runs, the enemies take turns, your shields stop what they "
				+ "stop — and the swing that gets past them opens the door. Its "
				+ "enemy comes with you, alive and following: escape answers the "
				+ "goal with a no, it does not delete the question."),
			_note("★ Rate is always optional and always available. Score a game "
				+ "out of ten and write a note; it feeds the Tier List, which is "
				+ "yours across every run and is not a game mechanic at all."),
		],
	}


# ---------------------------------------------------------------------------
# 4. Enemies are goals
# ---------------------------------------------------------------------------

static func _ch_enemies() -> Dictionary:
	return {
		"id": &"enemies", "icon": "☠", "title": "Enemies are goals",
		"blurb": "What they want, what they do if you refuse.",
		"blocks": [
			_p("Every game on the map has exactly one enemy standing on it, rolled "
				+ "from a pool matched to that game's type and the run's current "
				+ "difficulty. The enemy IS its goal. Killing it and doing the "
				+ "goal are the same act."),
			_h("Nothing arrives alone"),
			_p("Committing to a game spawns TWO bodies: its own enemy, and an "
				+ "escort rolled from the same pool — another enemy that could "
				+ "have been waiting there. The card warns you that a second one "
				+ "is coming but never says which; you find that out on arrival."),
			_b("Only the named enemy is the game's. Beating the game answers for "
				+ "it alone — the escort keeps its own goal, and clearing that is "
				+ "a job for a later game."),
			_b("So a missed goal now costs you two followers rather than one, and "
				+ "the escort's loot and gold are still there to be collected "
				+ "whenever you get round to its goal."),
			_b("A BOSS spawns alone. The tier change is the step up on its own."),
			_b("Scramble rerolls the pair. The escort came with the enemy you "
				+ "rejected, so it leaves with it."),
			_h("The three kinds of goal"),
			_kv("Bounty", "Defeat a specific thing in the real game. Defeat an "
				+ "enemy that splits. Defeat something that is an alien."),
			_kv("Restriction", "A rule you impose on your own play. You must "
				+ "randomly select your starting character."),
			_kv("Discovery", "See something happen. Witness an enemy kill itself."),
			_p("Your own statuses can bolt extra clauses onto a goal, and a boss's "
				+ "goal is a tighter version of an ordinary one — beat the true "
				+ "ending rather than just the ending. The card always shows the "
				+ "goal as it would actually be played, clauses included, so what "
				+ "you read is what you owe."),
			_h("What happens when you do not do it"),
			_p("The enemy does not vanish and it does not stay put. It follows you."),
			_b("It has been standing on the board since the moment you chose its "
				+ "game, at the back edge."),
			_b("Miss its goal and it starts walking during its own game. Crossing "
				+ "the board takes it a while — that is your grace period, and it "
				+ "is a distance rather than a rule."),
			_b("Once it reaches the front it attacks after every game you play, "
				+ "for its damage, forever, until its goal is met."),
			_b("Damage is 1 to 3, tracking the enemy's tier. A shield stops the "
				+ "whole swing if you have one; otherwise it all comes off Health."),
			_p("Followers stack. Two followers in reach is two hits every lost run; "
				+ "five is five. And on the Amulet's doorstep every one of them "
				+ "swings twice more for each game you hand in. This is how runs "
				+ "actually end."),
			_h("Old goals never expire"),
			_p("A follower's goal can be fulfilled during ANY later game. Do it "
				+ "and the follower dies right there, drops its loot and pays its "
				+ "gold, exactly as though you had beaten it on time."),
			_p("This is the single most useful thing to know. Three followers with "
				+ "goals like defeat an enemy that splits are three goals you can "
				+ "clear in one evening inside one unrelated game, if that game "
				+ "happens to have splitting enemies in it. Read your checklist "
				+ "before you pick where to go — sometimes the right card is the "
				+ "one that lets you pay off two old debts at once."),
			_note("A follower whose old goal you cleared this game holds its fire "
				+ "for the whole of that game — every turn of it. That makes "
				+ "old-goal clearing worth MORE the closer you are to the Amulet, "
				+ "which is the opposite of everything else on the pressure ladder."),
			_h("Other ways to be rid of one"),
			_b("A BOMB kills a normal enemy outright — they have 1 Health. No loot, "
				+ "no gold and no chest points, though: a bomb is an escape from a "
				+ "goal, not a way to farm one."),
			_h("What a body is worth"),
			_p("Two things, and they arrive at different moments. The LOOT drops "
				+ "on the square it died in, straight away, yours whatever the "
				+ "evening does afterwards. The RELICS are banked as chest points "
				+ "and paid on the reward screen — but only if you BEAT the game."),
			_p("Beating a game is worth one point on its own: a Small chest even "
				+ "if nothing was standing. Every body you clear makes that same "
				+ "chest bigger, by its own tier."),
			_row(["Body defeated", "Chest points"], true),
			_row(["Low", "+1"]),
			_row(["Medium", "+2"]),
			_row(["High", "+3"]),
			_row(["Insane", "+4"]),
			_p("Points climb the chest ladder — 1 Small, 2 Medium, 3 Large, 4 Huge "
				+ "— and past a Huge they split into a second chest rather than "
				+ "running off the end. Three High bodies on a game you beat is ten "
				+ "points: two Huge chests and a Medium."),
			_note("Bosses are not in that pool. A boss drops a chest of its own, "
				+ "on its own terms, and it is paid whether or not the game went "
				+ "your way."),
			_b("A BOSS takes no bomb damage at all and can only be removed by its "
				+ "goal."),
			_b("You cannot outrun anything. Moving to another game never drops a "
				+ "follower, and a Dash does not shake one off."),
		],
	}


# ---------------------------------------------------------------------------
# 5. The board
# ---------------------------------------------------------------------------

static func _ch_board() -> Dictionary:
	return {
		"id": &"board", "icon": "▦", "title": "The board",
		"blurb": "Where the enemies you owe are standing, and how close.",
		"blocks": [
			_p("The right-hand column is a grid with you on the left and the "
				+ "enemies on it. Columns are distance — column 1 is in your face, "
				+ "the last column is the far edge. Rows are lanes."),
			_p(("It starts at %dx%d. Every step up the difficulty ladder adds a "
				+ "column AND a row, so the board grows as the run gets harder: "
				+ "the tier that makes the enemies heavier also gives you more "
				+ "ground to lose before they arrive.")
				% [GameLoop2.BASE_GRID_COLS, GameLoop2.BASE_GRID_ROWS]),
			_h("What a body does"),
			_kv("Spawn", "It walks on at the back column the moment you choose its "
				+ "game. Its lane is picked at random from the ones it could "
				+ "actually reach you down."),
			_kv("Advance", "Each turn, anything not striking closes one column."),
			_kv("Strike", "It attacks the moment ANY of its cells is in column 1."),
			_p("Turns come from two places. Every run you LOSE at the game you "
				+ "are playing gives the board one, straight away. Handing the "
				+ "game in gives it only the EXTRA turns the Amulet's pull owes "
				+ "— none out in the wilds, up to two on its doorstep."),
			_h("Size is a real thing"),
			_p("Enemies are not all one cell. A body two cells wide reaches the "
				+ "front line in fewer games, because its leading edge starts "
				+ "closer. A body two cells tall plugs two lanes."),
			_p("An enemy occupies every solid cell of its shape and only moves "
				+ "when the whole shape can. So a big body is a wall: it jams the "
				+ "lanes behind it and anything queued up stalls until it moves or "
				+ "dies. Odd shapes have real gaps in them, and another body can "
				+ "stand in the notch."),
			_p("Each body carries what it does on the next game you report — ×2 "
				+ "for two swings, in 2 for two games of walking left. Read that "
				+ "number, not the column it is standing in."),
			_h("The two things you can do to the board"),
			_kv("✸ Bomb", "1 damage. Kills a normal enemy, does nothing to a boss "
				+ "except spend the charge. Arm the verb, then click the SQUARE "
				+ "you want it on — every square lights up, bodies and bare "
				+ "ground alike, and the CLICK is what spends the charge. Bare "
				+ "ground is worth bombing once the pack has made a blast leave "
				+ "something behind or reach past its own square."),
			_kv("⇤ Push", "Shove a follower one cell. Arm the verb, click the "
				+ "body, then press one of the arrows that appear. Nothing is "
				+ "spent until you press an arrow."),
			_note("Both verbs are armed first and aimed second, and arming either "
				+ "puts the other away. Cancel costs nothing."),
			_p("Pushing BACK buys a game. Pushing UP or DOWN changes its lane, "
				+ "which is the one move enemies can never make for themselves — "
				+ "so it is how you unplug a jammed lane, or plug a clear one. "
				+ "Forward is legal too, and that is your business."),
			_note("Clicking any body opens its card: its goal, its damage, its "
				+ "tier, and the verbs aimed at it."),
			_h("✦ Loot on the floor"),
			_p("A body you clear drops a piece of loot on the square it died in — "
				+ "a scroll, a pill or a potion, drawn as itself so you can see "
				+ "what it is from across the board — and it lies there for the "
				+ "rest of the game."),
			_p("DRAG IT to pick it up. Your pack appears beside the board while "
				+ "you are holding a piece, and goes away when you let go: drop it "
				+ "in a slot to carry it, or on the bin to throw it away. Clicking "
				+ "does nothing — hover it instead to read what it is."),
			_note("Pack full? Drop the piece onto one you are already carrying and "
				+ "the two TRADE: the new one goes in your pack and the old one "
				+ "lands on the square you took it from. Nothing is lost either "
				+ "way."),
			_p("A body walking onto a piece SHOVES it: to the nearest free "
				+ "square, and away from you when it has the choice. A board with "
				+ "no room left pushes it off the field."),
			_note("Nothing is ever lost by leaving one. Everything still on the "
				+ "floor when you report the game goes to the reward screen with "
				+ "the rest of the haul — win or lose, since the kill is what "
				+ "earned it."),
		],
	}


# ---------------------------------------------------------------------------
# 6. Health, shields and dying
# ---------------------------------------------------------------------------

static func _ch_health() -> Dictionary:
	return {
		"id": &"health", "icon": "♥", "title": "Health and dying",
		"blurb": "The two numbers that end a run.",
		"blocks": [
			_p("The whole survival model is two numbers, and they are deliberately "
				+ "tiny so they fit on a stream overlay."),
			_kv("Health", "Set by your character. Reaching 0 ends the run, "
				+ "immediately, wherever you are."),
			_kv("Shields", "Each stops one hit outright, however big. The "
				+ "Temporary ones a game grants expire when you report it; the "
				+ "plain ones stay until something breaks them."),
			_h("Everything that can take Health off you"),
			_b("A follower striking you, for 1 to 3, after every game — times the "
				+ "pressure multiplier."),
			_b("The turn every lost run hands the enemies — whatever the front "
				+ "line swings for, if no shield stops it."),
			_b("A few events and machines, which always say so before you press "
				+ "the button."),
			_p("Note what is NOT on that list. Taking a detour costs no Health. "
				+ "Failing a goal costs no Health directly — it costs you a "
				+ "follower, and the follower costs Health later. Nothing in this "
				+ "game hits you out of nowhere."),
			_h("Max Health"),
			_p("Items raise the cap, and raising the cap heals you by the same "
				+ "amount — a new heart arrives full. One relic deliberately "
				+ "arrives empty and says so on its own text. Lowering the cap "
				+ "takes the room and leaves the Health where it is, which only "
				+ "moves when it no longer fits."),
			_h("Levelling up"),
			_p("Your character carries a challenge that is offered every single "
				+ "game — beat a game without meta progression, unlock a new item, "
				+ "perfect a game. Meet it and you level, and you can level again "
				+ "the very next game. It is on the checklist with everything else "
				+ "and it is the most reliable income in the run."),
		],
	}


# ---------------------------------------------------------------------------
# 7. The verbs
# ---------------------------------------------------------------------------

static func _ch_verbs() -> Dictionary:
	return {
		"id": &"verbs", "icon": "⚗", "title": "The verbs",
		"blurb": "Bash, Dash, Transmute, Scramble, Push.",
		"blocks": [
			_p("Verbs are how you change the board instead of playing it. They are "
				+ "small integer charges, they come from drops, items and "
				+ "level-ups, and they are gone once spent. Four of them reshape "
				+ "what you are being offered; one reshapes the battlefield."),
			_h("On the offering"),
			_kv("⛏ Bash", "DESTROY a game outright. It leaves the pool for the "
				+ "whole run and can never be offered again. Its slot refills from "
				+ "the same pool the offering came from — another game connected "
				+ "to where you stand, with its own fresh enemy — and if there is "
				+ "nothing left to connect, the slot simply goes. Bash is "
				+ "destruction, not a guaranteed reroll."),
			_kv("⚗ Transmute", "Swap a game for a random one of the SAME TYPE that "
				+ "is off the map entirely — a game no route could ever have "
				+ "reached. It is the only way those games are ever played. The "
				+ "swap sticks to the SPOT: the node keeps all its connections, so "
				+ "the road out is unchanged and only the game you play there is "
				+ "different."),
			_kv("⚡ Dash", "A total select. Skip the offering and move to ANY "
				+ "connected game, not just the ones on the table."),
			_kv("🎲 Scramble", "Reroll the whole offering — new games, new enemies. "
				+ "At a node with no spare neighbours the games hold and only the "
				+ "enemies change, which is still often what you wanted."),
			_h("On the board"),
			_kv("⇤ Push", "Shove one follower one cell in any direction. See §5."),
			_h("What they are actually for"),
			_p("All of them are answers to a goal you cannot or will not do. Read "
				+ "the enemy on a card BEFORE deciding — that is the moment a "
				+ "Bash or a Transmute is worth spending, because after you travel "
				+ "the enemy is already on the board and only a bomb or the goal "
				+ "itself will move it."),
			_note("Two Bashes are refused outright: the Amulet game (destroying "
				+ "the win condition would make the run unwinnable) and the last "
				+ "card on the table with nothing to replace it."),
			_note("Traditional roguelikes have a setting of their own for "
				+ "Transmute. By default they swap for another Traditional game, "
				+ "which is arguably no relief at all — a Traditional game is the "
				+ "run's long haul. Turn on the other option in Settings and a "
				+ "Traditional game can transmute into any other type instead."),
		],
	}


# ---------------------------------------------------------------------------
# 8. Gold and shops
# ---------------------------------------------------------------------------

static func _ch_gold() -> Dictionary:
	return {
		"id": &"gold", "icon": "🛒", "title": "Gold and shops",
		"blurb": "The one reward you choose what to do with.",
		"blocks": [
			_p("Everything else the run pays you is a thing arriving — loot off "
				+ "a corpse, a chest off a level-up — and your only say is take it "
				+ "or leave it. Gold banks the decision instead."),
			_row(["Where gold comes from", "How much"], true),
			_row(["Enemy defeated", "+%d gold" % GameLoop2.GOLD_PER_ENEMY]),
			_row(["Boss defeated", "+%d gold" % GameLoop2.GOLD_PER_BOSS]),
			_row(["Item price", "%d plus the rarity rung — Common %d, Uncommon %d, "
				% [ShopSystem.BASE_PRICE, ShopSystem.BASE_PRICE, ShopSystem.BASE_PRICE + 1]
				+ "Rare %d, Legendary %d"
				% [ShopSystem.BASE_PRICE + 2, ShopSystem.BASE_PRICE + 3]]),
			_row(["Carries between runs", "None of it. A run opens on your "
				+ "character and nothing else."]),
			_p("A run is six to twelve games, so clearing most of your goals earns "
				+ "you somewhere around eight to fifteen gold — two to four "
				+ "purchases in a whole run. That is the point of the scale. Every "
				+ "purchase is supposed to cost you something."),
			_p("Gold rides the DROP, not the corpse. Beating an enemy on time pays; "
				+ "clearing an old goal games later pays exactly the same, because "
				+ "the goal was the price either way. Bombing pays nothing at all."),
			_h("Where the shops are"),
			_p(("A shop stands at each of the run's %d best-connected games — the "
				+ "genre's landmarks. Slay the Spire, Vampire Survivors, Isaac, "
				+ "Hades, Balatro and the rest. They are frozen at the start of "
				+ "the run, so a shop can never appear or vanish under you.")
				% RunGraph.NUM_HUBS),
			_p("This is the second routing axis and it is deliberately the "
				+ "opposite shape to an event. An event is a dead end — a two-game "
				+ "round trip. A hub is the MIDDLE of the map and rarely far off "
				+ "the road, so swinging through the big node is a cheap, "
				+ "repeatable decision rather than a committed detour."),
			_h("The shelf"),
			_b(("%d items, rolled once, and they STAY. Buying marks a slot sold "
				+ "rather than clearing it.") % ShopSystem.STOCK_SLOTS),
			_b("So a hub you cleared out is a hub you know is empty, and a hub you "
				+ "left two items at is a reason to walk back."),
			_b("The shop opens under the board when you beat the hub's game, and "
				+ "stays for the whole visit. Travelling on is what closes it."),
			_b("A Scramble charge rerolls the whole shelf, sold slots included."),
			_b("A shop card shows you what is left on a shelf you have already "
				+ "stood in — which is what makes going back a real decision. A "
				+ "shop you have never visited only tells you it is there."),
			_note("A hub pays NO EVENT. The shop is what happens there instead. "
				+ "That is the one way a hub card costs differently from every "
				+ "other card on the table."),
		],
	}


# ---------------------------------------------------------------------------
# 9. Events and machines
# ---------------------------------------------------------------------------

static func _ch_events() -> Dictionary:
	return {
		"id": &"events", "icon": "✦", "title": "Events and machines",
		"blurb": "What happens between the games.",
		"blocks": [
			_p("An EVENT fires after every game you play — won, lost, or escaped. "
				+ "The games this is a map of are hour-long roguelikes, and the "
				+ "event is the beat in between: a decision that takes a minute "
				+ "and costs something."),
			_b("Every game pays one, and is then spent for the rest of the run — "
				+ "so walking a two-node loop is not a way to farm them."),
			_b("A hub pays none. The shop is what happens there."),
			_b("A game you were SENT to by another event pays none, and neither "
				+ "does the Amulet, where the run is already over."),
			_b("Which event you get is dealt from a shuffle bag: nothing comes "
				+ "round again until the rest of the deck has been seen."),
			_p("Events give items, gold, Health, charges, curses and statuses, and "
				+ "some of them send you somewhere or ask you to go and play a "
				+ "specific kind of game. Read the buttons — every one of them "
				+ "says what it costs and what it pays before you press it, "
				+ "including the real odds on anything that gambles."),
			_h("Machines"),
			_p("A machine is a thing in the room rather than a room. An event ends "
				+ "when you answer it; a machine stands in front of you for as "
				+ "long as you are on that game, and travelling on is what ends "
				+ "it. Several can be there at once."),
			_p("Machines draw under the board where a shop does, and their buttons "
				+ "are greyed rather than hidden when you cannot use them — the "
				+ "button itself tells you why. Jammed. Full. Needs 1 Bomb. A "
				+ "machine is a physical object and its buttons do not disappear "
				+ "because you are broke."),
			_note("The Donation Machine's bank is the one number in this game that "
				+ "is not about the current run. It survives your death."),
		],
	}


# ---------------------------------------------------------------------------
# 10. What you carry
# ---------------------------------------------------------------------------

static func _ch_pack() -> Dictionary:
	return {
		"id": &"pack", "icon": "🎒", "title": "What you carry",
		"blurb": "Items, scrolls, statuses, curses and Luck.",
		"blocks": [
			_p("The strip above the board is your pack — relics and scrolls "
				+ "together, one row of tokens, because both are things you are "
				+ "carrying."),
			_h("Items"),
			_p("Every defeated enemy drops one, so the item table IS the reward "
				+ "economy. Most are passive and simply apply; some are Usable and "
				+ "carry their own button on the token; a few only fire on a "
				+ "trigger, like after beating a game or when a game is selected."),
			_p("Rarity runs Common, Uncommon, Rare, Legendary — and there are "
				+ "relics off that ladder entirely, from bosses and events, out of "
				+ "pools nothing else can reach."),
			_h("Scrolls"),
			_p("Scrolls arrive UNIDENTIFIED. You do not know what one does until "
				+ "you read it or identify it, and they are not all good — each "
				+ "has a leaning, positive, negative or neutral, and reading a "
				+ "mystery one is a real gamble."),
			_b("Reading one identifies that type forever. So does a Scroll of "
				+ "Identify — and one drop in ten is a Scroll of Identify, so the "
				+ "way out of not knowing is the most common thing you find. "
				+ "Amnesia can make you forget one again."),
			_b("The good ones stun an enemy for a turn, or teleport you across the "
				+ "map. The bad ones spawn an enemy, or hand every enemy on the "
				+ "board a permanent +1 Strength. Scroll of Fire is the one that "
				+ "cuts both ways: it sets the front column alight and you with "
				+ "it."),
			_h("Statuses"),
			_p("A status is first of all a clause bolted onto a GOAL, which is the "
				+ "only currency this game has. That is how an item or an event can "
				+ "make the run harder or easier without knowing anything about "
				+ "goals. It also does something on the BOARD."),
			_kv("A goal", "A standing objective of your own, offered every game and "
				+ "paid every time you meet it."),
			_kv("A clause", "ANDed onto goals and REQUIRED. On you, it tightens "
				+ "every enemy's goal. On an enemy, just that one's."),
			_kv("A bonus", "An optional extra objective, claimable for a reward and "
				+ "free to ignore."),
			_kv("A demand", "An obligation with a price. It pays nothing for being "
				+ "met, and charges you at the end of any game you did not meet it."),
			_kv("A way out", "An alternative to an enemy's goal — do this instead "
				+ "and that enemy is cleared. It counts as a clear and not as a "
				+ "win: nothing about it goes on the record, because you never did "
				+ "what it asked. Never offered on a boss."),
			_p("The five of them, and what they do in a fight:"),
			_kv("Strength", "Every hit that enemy lands is worth 1 more per stack."),
			_kv("Speed", "It closes one extra tile per stack, every turn — so it "
				+ "reaches you sooner than the board looks like it should."),
			_kv("Dexterity", "It gets a Shield per stack. Each one stops a whole hit "
				+ "and is spent doing it, so a shielded enemy takes an extra goal "
				+ "per shield to put down."),
			_kv("Marked", "Everything that lands on it is DOUBLED and goes straight "
				+ "through Shields. On YOU it is a debt as well: every game, get as "
				+ "many achievements in the game you are playing as you have stacks "
				+ "of it — or take 3 damage. On an ENEMY the same condition pays a "
				+ "chest instead, so a marked body is worth engaging."),
			_kv("Burn", "It hits for half. On YOU it is a debt instead: every game, "
				+ "skip or trash as many items in the game you are playing as you "
				+ "have stacks of it — or take 3 damage once the enemies have "
				+ "swung. Pay it and a stack comes off, which makes the next one "
				+ "cheaper. It stacks no higher than 3. On an ENEMY the same deal "
				+ "runs the other way: its goal grows a way out that costs 4 minus "
				+ "its stacks, so a badly burned enemy is the cheapest one to be "
				+ "rid of. Burn is bad for whoever is carrying it. And it burns "
				+ "PAPER: every time Burn lands on you there is a 1-in-4 chance "
				+ "that one random scroll in your pack goes up with it. Pills "
				+ "and potions are safe."),
			_b("The buffs are felt by enemies only. Marked is a debuff, and a debuff "
				+ "is felt by whoever is carrying it — Marked on YOU doubles every "
				+ "hit you take and goes straight past the shields you were "
				+ "counting on to stop it. Burn's halving is the exception that proves it is a "
				+ "column and not a rule about the word: there is no attack of "
				+ "yours for a halving to sit on, so the sheet says enemies only."),
			_h("The ground: tiles and units"),
			_p("Two things can be on a square of the board that are not a body, and "
				+ "they layer — a unit stands on top of a tile effect. Neither of "
				+ "them BLOCKS anything: an enemy walks in and whatever is there "
				+ "reacts. Wherever an item or a scroll names one, hover the chip "
				+ "under its description to read it."),
			_kv("Fire (a tile effect)", "Anything that walks into it, or starts its "
				+ "turn standing in it, takes +1 Burn — and so does anything the "
				+ "fire is lit UNDER, on the spot. A big body pays for every "
				+ "burning square it covers. It burns for 3 GAMES — not turns — "
				+ "wherever it is lit. Scroll of Fire lights the whole front "
				+ "column, Red Candle lights one square you pick in columns 2-3, "
				+ "and Hot Bombs leaves it on every square a bomb went off over."),
			_kv("Landmine (a unit)", "Steps on it, and it explodes: no Bomb of "
				+ "yours is spent, but it counts as one, so every bomb relic in "
				+ "your pack reads it — Brimstone widens the blast, Sticky stuns "
				+ "what lives, Blood Bombs heals you, Hot Bombs leaves fire in the "
				+ "crater. Like a bomb it destroys rather than defeats, so nothing "
				+ "drops. Landmines lays one after every game you finish."),
			_kv("The two together", "Fire and a mine cannot share a square. "
				+ "Whichever arrives second, the heat sets the mine off and the "
				+ "blast blows the fire out."),
			_b("Enemies steer around mines when they have anywhere else to go, and "
				+ "walk straight through them when they don't — a body in the lane "
				+ "is a wall that might never move, a mine is a toll paid once. So "
				+ "a minefield SHAPES where they come at you rather than stopping "
				+ "them."),
			_h("Curse goals"),
			_p("A curse goal is a row on your checklist you are trying NOT to "
				+ "complete. Break it and the penalty is always the same one: a "
				+ "random enemy spawns at the run's current difficulty. A curse "
				+ "bills you in the run's own currency rather than reaching for "
				+ "your Health bar."),
			_h("Luck"),
			_p("Every point of Luck buys one more roll, and the better result is "
				+ "kept. It compounds rather than adding — at 1 Luck a 25% chance "
				+ "is really 43.75%, and at 3 Luck it is 68%. It reaches every "
				+ "random decision the run makes: item rarity, chest sizes, shop "
				+ "stock, scrolls, machines."),
			_p("Negative Luck is the same machine backwards — extra rolls, keep "
				+ "the worse. And any odds the game shows you are the odds your "
				+ "Luck will actually roll, not the number on the sheet."),
		],
	}


# ---------------------------------------------------------------------------
# 11. Bosses and difficulty
# ---------------------------------------------------------------------------

static func _ch_bosses() -> Dictionary:
	return {
		"id": &"bosses", "icon": "⚠", "title": "Bosses and difficulty",
		"blurb": "The clock you ride, and what rides in on it.",
		"blocks": [
			_p("There are two difficulty axes. The pressure ladder in §2 is the "
				+ "one you steer. This is the one that ticks up on its own."),
			_p(("Every %d games you PLAY, the run's tier goes up: Low, Medium, "
				+ "High, Insane, and there it stops. A higher tier means enemies "
				+ "that hit harder — and a bigger board to cross before they reach "
				+ "you, which is the counterweight.") % RunDifficulty.GAMES_PER_TIER),
			_h("Boss rounds"),
			_p("When the tier changes, a boss round announces itself in a popup, "
				+ "once. It shows the bosses standing on the cards, and you can "
				+ "click any portrait to read its goal and its damage before you "
				+ "decide anything."),
			_p("A boss round is a different set of rules:"),
			_b("A boss's goal is a tighter version of an ordinary one — the true "
				+ "ending, not the ending; deathless, not merely won."),
			_b("It hits harder than the 1-to-3 band."),
			_b("It drops a Boss relic, out of a pool nothing else can reach."),
			_b("Bombs do it no damage at all. The goal is the only thing that "
				+ "removes it. You can still throw one — it spends the charge and "
				+ "does nothing, which is how a bomb that carries a stun on it "
				+ "reaches a boss."),
			_b("Bashing, transmuting or scrambling buys you a DIFFERENT boss, not "
				+ "a way past this one."),
			_note("A boss cannot be dashed past either. There is no route around a "
				+ "tier change — only through it."),
		],
	}


# ---------------------------------------------------------------------------
# 12. When it goes wrong
# ---------------------------------------------------------------------------

static func _ch_wrong() -> Dictionary:
	return {
		"id": &"wrong", "icon": "🛟", "title": "When it goes wrong",
		"blurb": "Recovery, in the order things actually go wrong.",
		"blocks": [
			_p("Every one of these is a normal Tuesday, not a mistake. This is the "
				+ "chapter to open when a run is going badly."),
			_h("I cannot do this goal"),
			_p("Decide BEFORE you travel, while the card is still open. Bash the "
				+ "game if you never want to see it again; Transmute it if you "
				+ "want a different game in the same spot with the road unchanged; "
				+ "Scramble the whole offering if none of the three appeal. Once "
				+ "you travel, the enemy is on the board and only a bomb or the "
				+ "goal itself will move it."),
			_h("I already travelled and I still cannot do it"),
			_p("Beat the game anyway. You move on, the enemy follows, and its goal "
				+ "goes on your checklist where you can clear it in some LATER "
				+ "game that happens to suit it. That is not a loss, it is a debt "
				+ "— and debts in this game are payable in any currency."),
			_h("I keep losing runs of this game"),
			_p("Each lost run hands the board a turn, and the board is closer "
				+ "every time. As soon as one of them gets through your shields "
				+ "and takes Health, Escape is offered: take it. Escaping keeps "
				+ "the enemy but stops the bleeding, and the goal stays on your "
				+ "checklist to clear somewhere friendlier."),
			_h("I have four followers and they are killing me"),
			_p("In rough order of what to try:"),
			_b("ROUTE AWAY from the Amulet. Getting back to five or more hops "
				+ "takes the extra turns away entirely — the board stops moving "
				+ "except when you lose a run. That is the biggest single lever in "
				+ "the game and it costs only games."),
			_b("Pick cards whose games can pay off SEVERAL old goals at once. Read "
				+ "the checklist first and choose the game to fit it, rather than "
				+ "the other way round."),
			_b("Clear an old goal even if you cannot clear this game's — a "
				+ "follower you engaged holds its fire for the whole game."),
			_b("Bomb the ordinary enemies. No drop and no gold, but a dead enemy "
				+ "is a dead enemy."),
			_b("Push the front-line body backwards to buy a game, or sideways to "
				+ "unjam a lane."),
			_b("Clear a game first try. Nothing you never lost is a turn the "
				+ "stack never took, and the whole shield pool is still standing "
				+ "when you report — a stack that cannot reach your Health is a "
				+ "stack you can outlast."),
			_h("The offering is all dead ends"),
			_p("Dash is a total select — it ignores the offering and lets you move "
				+ "to any connected game at all. It is the right answer to a bad "
				+ "table far more often than people spend it."),
			_h("I want to stop"),
			_p("Save and quit from the menu. Nothing decays, nothing expires, and "
				+ "the run will be exactly where you left it. You are meant to be "
				+ "away playing something else — that is the game."),
		],
	}


# ---------------------------------------------------------------------------
# 13. Where every number is
# ---------------------------------------------------------------------------

static func _ch_screen() -> Dictionary:
	return {
		"id": &"screen", "icon": "◎", "title": "Where every number is",
		"blurb": "A map of the screen. Nothing is drawn twice.",
		"blocks": [
			_p("There is no HUD strip. Every number is drawn once, by whatever "
				+ "owns it, which takes a moment to learn and then never gets in "
				+ "the way."),
			_kv("Health, shields, statuses", "On the hero, on the left of the "
				+ "board. Hearts under the portrait, one shield over it per shield "
				+ "you have — the ones that stay nearest your face, the Temporary "
				+ "ones after them with a clock on them. Anything wearing that "
				+ "clock is going away, statuses included."),
			_kv("Gold", "A chip in the top bar."),
			_kv("Board size and tier", "The right-hand end of the board's pressure "
				+ "bar."),
			_kv("Extra turns", "The strip across the top of the board: what "
				+ "reporting a game hands the enemies, in the band's colour, with "
				+ "the hop count that caused it. Zero out in the wilds."),
			_kv("Push and Bomb charges", "On their own buttons, on the board's "
				+ "toolbar."),
			_kv("Bash, Dash, Transmute, Scramble", "Chips on the row under the "
				+ "offering. Dash and Scramble are buttons; Bash and Transmute "
				+ "need a target, so you press them inside a game's card."),
			_kv("Tries a game would grant", "On the offering's hover line, and in "
				+ "full on the card."),
			_kv("What is waiting at a game", "Hover its cover: the enemy's picture "
				+ "and its goal, on one line under the offering."),
			_kv("Anything else on the page", "Hover it. An enemy, a status, a relic "
				+ "and the enemy-turns readout each show a small card — the short "
				+ "version of what clicking them opens."),
			_kv("Where you have been", "The strip across the top: every game you "
				+ "have played, in order, with a dashed arrow to the Amulet."),
			_kv("What you owe", "The checklist, left column."),
			_kv("What is chasing you", "The board, right column."),
			_h("Elsewhere in the menus"),
			_kv("🗺 Map", "The whole route to the Amulet, zoomable, with every "
				+ "shop marked. It lives in the offering's heading row."),
			_kv("✦ Atlas", "The entire influence graph as a star chart. Not a run "
				+ "tool — a thing to look at."),
			_kv("Collection", "Every item, scroll, enemy, event and status in the "
				+ "game, and whether you have met it."),
			_kv("🏆 Tier List", "Your own ranking of every game you have beaten, "
				+ "across all runs, with the notes you wrote at the time."),
			_kv("⚙ Custom Run", "Build a run out of a chosen slice of the catalog "
				+ "— which games can be on the map, which can start it, which can "
				+ "be the Amulet, and how long the road is."),
		],
	}
