# Rules — as the player sees them

> **Generated** from the in-game manual (📖 How to Play, `scripts/ui/HowToPlayText.gd`) by `tools/dump_rules_doc.gd` — edit the manual, not this page. Every number here is read off the constant the game itself uses, so this page and the game cannot disagree. The design reasoning behind the rules is in [`games-first-redesign.md`](games-first-redesign.md).

## Contents

1. [Start here](#-start-here) — The whole game in one page.
2. [Choosing where to go](#-choosing-where-to-go) — The offering, the card, and the route to the Amulet.
3. [Playing the game](#-playing-the-game) — Shields, lost runs, the checklist, getting out, and making camp.
4. [Enemies are goals](#-enemies-are-goals) — What they want, what they do if you refuse.
5. [The board](#-the-board) — Where the enemies you owe are standing, and how close.
6. [Health and dying](#-health-and-dying) — The two numbers that end a run.
7. [The verbs](#-the-verbs) — Bash, Dash, Transmute, Scramble, Push.
8. [Gold and shops](#-gold-and-shops) — The one reward you choose what to do with.
9. [Events and machines](#-events-and-machines) — What happens between the games.
10. [What you carry](#-what-you-carry) — Items, scrolls, statuses, curses and Luck.
11. [Bosses and difficulty](#-bosses-and-difficulty) — The clock you ride, and what rides in on it.
12. [Fractures](#-fractures) — Ten harder runs, unlocked one at a time.
13. [When it goes wrong](#-when-it-goes-wrong) — Recovery, in the order things actually go wrong.
14. [Where every number is](#-where-every-number-is) — A map of the screen. Nothing is drawn twice.

## ▶ Start here

*The whole game in one page.*

The dungeon is your backlog. Every room on the map is a real roguelike that really exists, and the way you fight through a room is to go away, open that game, and play it. This app is the Dungeon Master: it decides what you have to do in there, and it takes your word for whether you did it.

There is no combat here to play. The combat is Hades.

### One run, start to finish

1. Pick a character. That sets your Health and the charges you start with.
2. Pick where you start. You are offered three games, and the one you take is the run's first game — not a free move. The Amulet is named on this panel, and every card says how many games away it is, so you are choosing a road knowing where it ends.
3. The game you took has TWO ENEMIES walking onto the board, and each enemy is a GOAL: something to do inside the real game. Beat a boss without healing. Descend ten floors. Win in one deck cycle. Beating the game answers for neither of them — each goal is its own.
4. Go and play it. Actually play it — this is the part that takes an evening, and it is the whole point.
5. Come back and press Completed Game, and tick whichever goals you actually did on the way. Nobody is checking. That is the honour system and it is load-bearing.
6. A goal you ticked: that enemy dies, drops a piece of loot on the board, pays a gold, and makes the chest waiting on the reward screen bigger. One you left unticked: it survives, follows you, walks a column closer for every run you lose, and hits you on every lost run once it reaches the front.

Two rows on that list do not behave like a plain tick box. A goal that COUNTS something — Defeat 3 bugs — is a + button with a running total beside it instead, and only the press that reaches the number resolves anything; − takes a misclick back, and the tally follows the enemy into later games, so the three need not all be in one. A goal that says Beat a game without something waits for the game to be beaten: tick it whenever, but nothing happens until you hand the game in, and reporting a loss drops the claim.

7. You are offered a new set of games, connected to where you stand. Each card wears a mark saying what kind of place it is: ! two enemies, !! a boss, ? an event, $ a shop. Choose one. Go to 3.

The run ends when you reach and clear the AMULET game — that is the win — or when your Health hits zero.

### What makes it a game rather than a list

Three things, and they are the three chapters after this one.

- The map is the real influence graph of the genre. Rogue connects to NetHack connects to Spelunky. You can only travel along edges that are actually there, so where you can go next is decided by what you just played.
- Enemies you did not beat do not go away. They pile up, they all hit you, and they keep hitting until you go back and finish their goals — and losing at a game without putting anything down brings MORE of them. A run does not kill you; a backlog does.
- The closer you get to the Amulet, the faster everything chasing you moves. Rushing the win and taking the long way are both real strategies, and which one is right depends on what is on your tail.

> You never have to finish a game in one sitting, and the app does not care how long you take. Save the run and close it. It will be here when the game is.

## 🗺 Choosing where to go

*The offering, the card, and the route to the Amulet.*

After every game you are shown an OFFERING: a few cover cards, drawn from the games connected to the one you are standing on. This is the only decision the app actually asks you to make, so it is the one with everything behind it.

### Click the card, do not just take it

Clicking a card OPENS it rather than travelling to it. The card itself is only the cover, the name, its KIND mark, and a flag if it is the Amulet or a shop. Everything you need is inside.

- **The kind** — What stands there, fixed for the whole run: ! Enemies (two bodies walk on), !! Champion (a boss, alone), ? Event (an event the moment you arrive, no bodies), $ Shop (a shelf once you beat the game, no bodies). The 🗺 map and the route ladder mark every node the same way, so the road ahead can be read before you walk it.
- **The route** — The optimal path from that game to the Amulet, drawn as the real ladder — so you can see what taking this card does to the road, not just where it puts you.
- **The enemy** — Who is waiting there, and the exact goal you would be playing for, written out with any clauses your own statuses add to it — plus a line saying how many bodies walk on, which is the node's kind: two, one boss, or none.
- **The shields** — How many Temporary Shields that game hands you — one hit stopped each. See §3.
- **The pace** — What taking it does to how fast the board moves — speeds up, slows down, or no change.
- **Connections** — How many games it opens onto, how many of those still owe you an event, and how many are shops.
- **Your record** — Whether you have beaten it before, in this run and in your life.

### The route badge

- **★ OPTIMAL — N steps left** — This card is on a shortest path to the Amulet. Taking it spends a game and buys a step.
- **↩ Detour +N** — This card is off the shortest path. It costs you N extra games to come back from.
- **🏆 THE AMULET** — This is the game the run is a search for. Beat the game and the run is won, whether or not its boss went down.

### Pressure: why the long way is a real option

Only one thing moves the board: a run you LOSE, one turn each. Handing a game in moves nobody. What the end of a game does instead is FILL the board — new enemies walk on at the back, and how many is read off how close you are to the Amulet:

| Hops to the Amulet | Enemies per game | Band |
| --- | --- | --- |
| 5 or more | 0 | Distant |
| 3 – 4 | 1 | Closing |
| 2 or fewer | 2 | Doorstep |

This is the whole reason routing is a decision. Route wide and the board fills slowly; run at the Amulet and every game you finish puts more on it, shoving the ones already there closer when the back is full. Neither is correct in general — what decides it is how full your board already is.

> Taking the Amulet card itself carries no pace warning. There is no next game for the enemies to act in — you have either won or you have not.

## 🎮 Playing the game

*Shields, lost runs, the checklist, getting out, and making camp.*

You have chosen a game. The app now does nothing until you come back — go and play. What follows is what the screen is for while you are away and when you return.

### Shields are hits you do not take

A SHIELD stops ONE INSTANCE of damage — the whole of it, however big. A 3-damage swing breaks one shield and lands for nothing; so does a 1-damage one. They are drawn as pips over your character.

There are two kinds, and the only difference is whether they survive the game:

- **Temporary Shields** — What selecting a game hands you. They EXPIRE when you report it — they are that game's armour and nobody else's.
- **Shields** — Gained off the board (a pill, a relic). They STAY until something breaks one, so they are worth carrying toward a game you expect to hurt.
- **Any game grants** — 3 Temporary Shields
- **A Traditional roguelike** — 5 — the long haul gets more

A hit breaks a Temporary Shield first, every time. They are the ones about to expire anyway, so spending the pool that survives while one of them is still standing would be the wrong way round.

### Losing a run gives the enemies a turn

A roguelike is not beaten in one sitting, and you will lose runs of it. Every time you do, you tick the attempt tracker yourself, and each tick hands the enemies A TURN: the front line swings and everything behind it walks a column closer. Nothing else moves the board — handing a game in does not.

It costs you no shields of either kind. There is no limit on how many times you may fail at a game — what there is, is a board that is one turn closer every time you do, and a pool that is one shield smaller each time a swing gets through.

So a game you clear first try never lets the stack move at all. A game that fights back walks it into your face and then makes you report from there. That is the tension the whole run is built on: your Health is only ever in danger when you are already having a bad time.

> There is no undo on the tracker. A tick hands the enemies a turn and the turn stands — press it when you have actually lost a run, not to see what happens.

### The checklist

The left column is everything you are trying to do inside the real game, in one list:

- Every follower's outstanding goal — old goals can be cleared at any time, in any game, and doing so kills that follower exactly as if you had beaten it on time.
- Your character's level-up challenge, which is a fresh chance every single game.
- Any standing objectives your statuses have added.

Hover a row and the body it belongs to lights up on the board. Hover a body and its row lights up. They are the same fact written twice.

### A tick happens NOW

Tick a row the moment you do the thing. It asks you to confirm, and then it RESOLVES — mid-game, while you are still playing. The enemy dies and drops its loot onto the board. The reward is paid. The level is taken.

You do not have to finish the game first, and losing runs does not stop you: a goal you cleared in the first hour is worth something for the rest of the evening rather than sitting there waiting for you to press a button.

> There are no take-backs. The confirm is the safeguard — an enemy that is already dead cannot be un-killed.

### Reporting

Press Completed Game when you are done with the game — done, not necessarily victorious. Two different things are being claimed, and they are claimed separately:

- **The button** — Says you played and finished the real game. That is what counts it as beaten, pays the return-trip Dash, and wins the run at the Amulet.
- **The tick boxes** — One per enemy on the board — including whatever walked on when you took this game. Ticking one says you did that enemy's goal, and doing that is what kills it. They are answered as you go, though, so by the time you press the button they are usually all settled.

So you can finish a game and leave everything on the board still following you, or clear three old goals during a game you never finished. Neither is a failure state; an unticked enemy is a debt.

> Nothing on the board belongs to the game you are playing. What walked on with it is a follower like every other body from the moment it lands — you can bomb it, push it, or leave its goal for three games and clear it later.

### Escaping

If a game is going nowhere you can leave it — once you have LOST 3 RUNS of it, or just 1 of a Traditional roguelike, where one run can be a whole evening. The count starts again at every game you land on, so escape is for the game you have tried and cannot beat, not for the one you would rather not try.

Walking out ends the game, so the board fills behind you. If you put a body down to its goal here, it costs exactly what handing the game in would; if you put nothing down, it costs one more and never fewer than 2. Either way there is no chest. The enemy comes with you, alive and following: escape answers the goal with a no, it does not delete the question.

### Ending a session: make camp

A run lasts more than one sitting, so end each one by making camp. When you leave the run (Exit, or Main menu) having beaten a game since your last camp, you are offered Make camp first — even with a game still in play. It offers two cards and you take one. REST is always there: +2 Health. The other is dealt from one of the games you beat since the last camp, by its type — a Traditional game lets you identify a piece of loot, a Deckbuilder hands you a random card, a Strategy game puts 2 charges into something you carry, and an Action game gives you 1 Shield that stays. Taking a card saves the run and returns you to the main menu. Going back to the run instead keeps the same two cards for the next time you leave.

> ★ Rate is always optional: it is on the card a game opens and on the screen a game ends on. Score a game out of ten and write a note; it feeds the Tier List, which is yours across every run and is not a game mechanic at all.

## ☠ Enemies are goals

*What they want, what they do if you refuse.*

An enemy is rolled from a pool matched to the game's type and the run's current difficulty. The enemy IS its goal. Killing it and doing the goal are the same act.

### What a node stands up

How many bodies a game puts on the board is decided by the NODE, not by the game. An Enemies node stands TWO — its own enemy and a second rolled from the same pool. A Champion node stands ONE: a boss of the run's current tier, alone. An Event or a Shop node stands none at all. The card says how many; which ones is rolled on arrival.

- Neither of the two is a companion to the other. Both carry their own goal, both are ordinary followers from the moment they land, and beating the game answers for neither of them on its own.
- So a missed goal costs you two followers rather than one, and both lots of loot and gold are still there to be collected whenever you get round to their goals.
- Scramble rerolls the pair. Both arrived with the game you rejected, so both leave with it.

### The three kinds of goal

- **Bounty** — Defeat a specific thing in the real game. Defeat an enemy that splits. Defeat something that is an alien.
- **Restriction** — A rule you impose on your own play. Beat a game without using magic. Most of these are settled by FINISHING the game — their box waits for the report rather than resolving the moment you tick it.
- **Discovery** — See something happen. Witness an enemy kill itself.

Your own statuses can bolt extra clauses onto a goal, and a boss's goal is a tighter version of an ordinary one — beat the true ending rather than just the ending. The card always shows the goal as it would actually be played, clauses included, so what you read is what you owe.

### What happens when you do not do it

The enemy does not vanish and it does not stay put. It follows you.

- It has been standing on the board since the moment you chose its game, at the back edge.
- It closes one column every TURN the board takes — one for every run you lose, and nothing else. Crossing the board takes it a while; that is your grace period, and it is a distance rather than a rule. Hover or click it for the count in lost runs.
- Once it reaches the front it strikes on every one of those turns, for its damage, until its goal is met.
- An ordinary enemy hits for 1 to 4; a boss for 3 to 9. A shield stops the whole swing if you have one; otherwise it all comes off Health.

Followers stack. Two followers in reach is two hits every lost run; five is five. This is how runs actually end.

### Every game that ends brings more of them

When a game ends — handed in or escaped — fresh bodies walk on at the back, rolled for the game you were playing. How many is read off the distance to the Amulet, not the difficulty:

| Hops to the Amulet | Bodies |
| --- | --- |
| 5 or more | 0 |
| 3 – 4 | 1 |
| 2 or fewer | 2 |

- +1 if you did not beat a single body's goal during the game. A bomb, a wand or a mine killing one does not count — only a goal you beat does.
- Escaping with nothing down adds that 1 too and never costs fewer than 2; escaping after a goal you beat costs the same as handing the game in.
- Nothing walks on at the Amulet, and nothing when a teleport pulls you out.
- A lane packed at the back gets SHOVED forward to make room — the whole line steps a column closer, and nobody takes a turn. The newcomer picks the lane that needs the least shoving. When no lane can go forward, the body in its way steps one lane up or down instead, if there is a free cell. A spawner that never attacks is never shoved forward, only aside.
- The strip on top of the board says the price before you pay it: +N when this game ends, or none, and why.

### Difficulty up

Every 4th spawn — a node's enemies arriving, or a game's end standing some up — is a DIFFICULTY UP: the tier steps, the board grows, and a boss walks on. The strip counts down to it.

### Old goals never expire

A follower's goal can be fulfilled during ANY later game. Do it and the follower dies right there, drops its loot and pays its gold, exactly as though you had beaten it on time.

This is the single most useful thing to know. Three followers with goals like defeat an enemy that splits are three goals you can clear in one evening inside one unrelated game, if that game happens to have splitting enemies in it. Read your checklist before you pick where to go — sometimes the right card is the one that lets you pay off two old debts at once.

> A follower too tough to fall to one goal (2 Health, or a shield) takes the hit, stays standing, and is STUNNED for two turns — two lost runs where it neither strikes nor steps.

### Other ways to be rid of one

- A BOMB kills a normal enemy outright — they have 1 Health. No loot, no gold and no chest points, though: a bomb is an escape from a goal, not a way to farm one.

### What a body is worth

Two things, and they arrive at different moments. The LOOT drops on the square it died in, straight away, yours whatever the evening does afterwards. The RELICS are banked as chest points and paid on the reward screen — but only if you BEAT the game.

Beating a game is worth one point on its own: a Small chest even if nothing was standing. Every body you clear makes that same chest bigger, by its own tier.

| Body defeated | Chest points |
| --- | --- |
| Low | +1 |
| Medium | +2 |
| High | +3 |
| Insane | +4 |

Points climb the chest ladder — 1 Small, 2 Medium, 3 Large, 4 Huge — and past a Huge they split into a second chest rather than running off the end. Three High bodies on a game you beat is ten points: two Huge chests and a Medium.

> Bosses are not in that pool. A boss drops a chest of its own, on its own terms, and it is paid whether or not the game went your way.

- A BOSS takes no bomb damage at all and can only be removed by its goal.
- You cannot outrun anything. Moving to another game never drops a follower, and a Dash does not shake one off.

## ▦ The board

*Where the enemies you owe are standing, and how close.*

The right-hand column is a grid with you on the left and the enemies on it. Columns are distance — column 1 is in your face, the last column is the far edge. Rows are lanes.

It starts at 4x4. Every step up the difficulty ladder adds a column AND a row, so the board grows as the run gets harder: the tier that makes the enemies heavier also gives you more ground to lose before they arrive.

### What a body does

- **Spawn** — It walks on at the back column — the moment you choose its game, or as a game ends. Its lane is picked at random from the ones it could actually reach you down; with every lane full at the back, it shoves the least-packed one forward instead.
- **Advance** — Each turn, anything not striking closes one column.
- **Strike** — It attacks the moment ANY of its cells is in column 1.

Turns come from one place: every run you LOSE at the game you are playing gives the board one, straight away. Handing the game in gives it none. So a body's column is its countdown — hover it or click it to have that said in words.

### Size is a real thing

Enemies are not all one cell. A body two cells wide reaches the front line in fewer games, because its leading edge starts closer. A body two cells tall plugs two lanes.

An enemy occupies every solid cell of its shape and only moves when the whole shape can. So a big body is a wall: it jams the lanes behind it and anything queued up stalls until it moves or dies. Odd shapes have real gaps in them, and another body can stand in the notch.

Each body carries what it does on the next game you report — ×2 for two swings, in 2 for two games of walking left. Read that number, not the column it is standing in.

### The two things you can do to the board

- **✸ Bomb** — 1 damage. Kills a normal enemy, does nothing to a boss except spend the charge. Arm the verb, then click the SQUARE you want it on — every square lights up, bodies and bare ground alike, and the CLICK is what spends the charge. Bare ground is worth bombing once the pack has made a blast leave something behind or reach past its own square.
- **⇤ Push** — Shove a follower one cell. Arm the verb, click the body, then press one of the arrows that appear. Nothing is spent until you press an arrow.

> Both verbs are armed first and aimed second, and arming either puts the other away. Cancel costs nothing.

Pushing BACK buys a game. Pushing UP or DOWN changes its lane, which is the one move enemies can never make for themselves — so it is how you unplug a jammed lane, or plug a clear one. Forward is legal too, and that is your business.

> Clicking any body opens its card: its goal, its damage, its tier, and the verbs aimed at it.

### ✦ Loot on the floor

A body you clear drops a piece of loot on the square it died in — a scroll, a pill or a potion, drawn as itself so you can see what it is from across the board — and it lies there for the rest of the game.

DRAG IT to pick it up. Your pack appears beside the board while you are holding a piece, and goes away when you let go: drop it in a slot to carry it, or on the bin to throw it away. Clicking does nothing — hover it instead to read what it is.

> Pack full? Drop the piece onto one you are already carrying and the two TRADE: the new one goes in your pack and the old one lands on the square you took it from. Nothing is lost either way.

A body walking onto a piece SHOVES it: to the nearest free square, and away from you when it has the choice. A board with no room left pushes it off the field.

> Nothing is ever lost by leaving one. Everything still on the floor when you report the game goes to the reward screen with the rest of the haul — win or lose, since the kill is what earned it.

## ♥ Health and dying

*The two numbers that end a run.*

The whole survival model is two numbers, and they are deliberately tiny so they fit on a stream overlay.

- **Health** — Set by your character. Reaching 0 ends the run, immediately, wherever you are.
- **Shields** — Each stops one hit outright, however big. The Temporary ones a game grants expire when you report it; the plain ones stay until something breaks them.

### Everything that can take Health off you

- A follower striking you on a turn — every lost run hands the board one, and reporting a game near the Amulet hands it the extra turns on the pressure ladder.
- A few events and machines, which always say so before you press the button.

Note what is NOT on that list. Taking a detour costs no Health. Failing a goal costs no Health directly — it costs you a follower, and the follower costs Health later. Nothing in this game hits you out of nowhere.

### Max Health

Items raise the cap, and raising the cap heals you by the same amount — a new heart arrives full. One relic deliberately arrives empty and says so on its own text. Lowering the cap takes the room and leaves the Health where it is, which only moves when it no longer fits.

### Levelling up

Your character carries a challenge that is offered every single game — beat a game without meta progression, unlock a new item, perfect a game. Meet it and you level, and you can level again the very next game. It is on the checklist with everything else and it is the most reliable income in the run.

## ⚗ The verbs

*Bash, Dash, Transmute, Scramble, Push.*

Verbs are how you change the board instead of playing it. They are small integer charges, they come from drops, items and level-ups, and they are gone once spent. Four of them reshape what you are being offered; one reshapes the battlefield.

### On the offering

- **⛏ Bash** — DESTROY a game outright. It leaves the pool for the whole run and can never be offered again. Its slot refills from the same pool the offering came from — another game connected to where you stand, with its own fresh enemy — and if there is nothing left to connect, the slot simply goes. Bash is destruction, not a guaranteed reroll.
- **⚗ Transmute** — Swap a game for a random one, of any type, that is off the map entirely — a game no route could ever have reached. It is the only way those games are ever played. The swap sticks to the SPOT: the node keeps all its connections, so the road out is unchanged and only the game you play there is different.
- **⚡ Dash** — A total select. Skip the offering and move to ANY connected game, not just the ones on the table.
- **🎲 Scramble** — Reroll the whole offering — new games, new enemies. At a node with no spare neighbours the games hold and only the enemies change, which is still often what you wanted.

### On the board

- **⇤ Push** — Shove one follower one cell in any direction. See §5.

### What they are actually for

All of them are answers to a goal you cannot or will not do. Read the enemy on a card BEFORE deciding — that is the moment a Bash or a Transmute is worth spending, because after you travel the enemy is already on the board and only a bomb or the goal itself will move it.

> Three Bashes are refused outright: the Amulet game (destroying the win condition would make the run unwinnable), the last card on the table with nothing to replace it, and a CHAMPION node (!!) — a boss cannot be bashed out of the road. Scramble the offering instead and you are dealt a different fight.

> Traditional roguelikes have a setting of their own for Transmute. By default they swap for another Traditional game, which is arguably no relief at all — a Traditional game is the run's long haul. Turn on the other option in Settings and a Traditional game can transmute into any other type instead.

## 🛒 Gold and shops

*The one reward you choose what to do with.*

Everything else the run pays you is a thing arriving — loot off a corpse, a chest off a level-up — and your only say is take it or leave it. Gold banks the decision instead.

| Where gold comes from | How much |
| --- | --- |
| Enemy defeated | +1 gold |
| Boss defeated | +3 gold |
| Item price | 3, and 2 more a rarity — Common 3, Uncommon 5, Rare 7, Legendary 9 |
| Loot price | 2 less than an item of its rarity, never under 2 |
| Carries between runs | None of it. A run opens on your character and nothing else. |

A run is six to twelve games, so clearing most of your goals earns you somewhere around eight to fifteen gold — two to four purchases in a whole run. That is the point of the scale. Every purchase is supposed to cost you something.

Gold rides the DROP, not the corpse. Beating an enemy on time pays; clearing an old goal games later pays exactly the same, because the goal was the price either way. Bombing pays nothing at all.

### Where the shops are

A shop stands at every SHOP NODE — the `$` on a card, on the map and on the route. About one game in ten on the map is one, dealt when the run begins and fixed from then on, so a shop can never appear or vanish under you.

Every start you are offered has at least one somewhere on its shortest roads to the Amulet, and the map shows the rest. A shop one step off the straight road is often the better way to go.

### The shelf

- 3 items, rolled once, and they STAY. Buying marks a slot sold rather than clearing it.
- So a shop you cleared out is a shop you know is empty, and a shop you left two items at is a reason to walk back.
- Beat the game there and a 🛒 Shop button appears by the games to choose from. It stays for the whole visit; travelling on is what takes it away.
- A Scramble charge rerolls the whole shelf, sold slots included.
- A shop card shows you what is left on a shelf you have already stood in — which is what makes going back a real decision. A shop you have never visited only tells you it is there.

> A Shop node pays NO EVENT. The shop is what happens there instead. Transmute the game on one and it still sells — the shop belongs to the spot on the map, not to the game.

## ✦ Events and machines

*What happens between the games.*

An EVENT fires after every game you play — won, lost, or escaped. The games this is a map of are hour-long roguelikes, and the event is the beat in between: a decision that takes a minute and costs something.

- Every game pays one, and is then spent for the rest of the run — so walking a two-node loop is not a way to farm them.
- A Shop node pays none. The shop is what happens there.
- An EVENT node (?) fires one the moment you ARRIVE, before you play — and always finds one, even at a node that has paid before.
- A game you were SENT to by another event pays none, and neither does the Amulet, where the run is already over.
- Which event you get is dealt from a shuffle bag: nothing comes round again until the rest of the deck has been seen.

Events give items, gold, Health, charges, curses and statuses, and some of them send you somewhere or ask you to go and play a specific kind of game. Read the buttons — every one of them says what it costs and what it pays before you press it, including the real odds on anything that gambles.

### Machines

A machine is a thing in the room rather than a room. An event ends when you answer it; a machine stands in front of you for as long as you are on that game, and travelling on is what ends it. Several can be there at once.

Machines draw under the board, and their buttons are greyed rather than hidden when you cannot use them — the button itself tells you why. Jammed. Full. Needs 1 Bomb. A machine is a physical object and its buttons do not disappear because you are broke.

> The Donation Machine's bank is the one number in this game that is not about the current run. It survives your death.

## 🎒 What you carry

*Items, scrolls, statuses, curses and Luck.*

The strip above the board is your pack — relics and scrolls together, one row of tokens, because both are things you are carrying.

### Items

Every defeated enemy drops one, so the item table IS the reward economy. Most are passive and simply apply; some are Usable and carry their own button on the token; a few only fire on a trigger, like after beating a game or when a game is selected.

Rarity runs Common, Uncommon, Rare, Legendary — and there are relics off that ladder entirely, from bosses and events, out of pools nothing else can reach.

### Scrolls

Scrolls arrive UNIDENTIFIED. You do not know what one does until you read it or identify it, and they are not all good — each has a leaning, positive, negative or neutral, and reading a mystery one is a real gamble.

- Reading one identifies that type forever. So does a Scroll of Identify — and one drop in ten is a Scroll of Identify, so the way out of not knowing is the most common thing you find. Amnesia can make you forget one again.
- The good ones Stun an enemy — it loses that many turns — or teleport you across the map. The bad ones spawn an enemy, or hand every enemy on the board a permanent +1 Strength. Scroll of Fire is the one that cuts both ways: it sets the front column alight and you with it.

### Statuses

A status is first of all a clause bolted onto a GOAL, which is the only currency this game has. That is how an item or an event can make the run harder or easier without knowing anything about goals. It also does something on the BOARD.

- **A goal** — A standing objective of your own, offered every game and paid every time you meet it.
- **A clause** — ANDed onto goals and REQUIRED. On you, it tightens every enemy's goal. On an enemy, just that one's.
- **A bonus** — An optional extra objective, claimable for a reward and free to ignore.
- **A demand** — An obligation with a price. It pays nothing for being met, and charges you at the end of any game you did not meet it.
- **A way out** — An alternative to an enemy's goal — do this instead and that enemy is cleared. It counts as a clear and not as a win: nothing about it goes on the record, because you never did what it asked. Never offered on a boss.

The five of them, and what they do in a fight:

- **Strength** — Every hit that enemy lands is worth 1 more per stack.
- **Speed** — It closes one extra tile per stack, every turn — so it reaches you sooner than the board looks like it should.
- **Dexterity** — It gets a Shield per stack. Each one stops a whole hit and is spent doing it, so a shielded enemy takes an extra goal per shield to put down.
- **Marked** — Everything that lands on it is DOUBLED and goes straight through Shields. On YOU it is a debt as well: every game, get as many achievements in the game you are playing as you have stacks of it — or take 3 damage. On an ENEMY the same condition pays a chest instead, so a marked body is worth engaging.
- **Burn** — It hits for half. On YOU it is a debt instead: every game, skip or trash as many items in the game you are playing as you have stacks of it — or take 3 damage once the enemies have swung. Pay it and a stack comes off, which makes the next one cheaper. It stacks no higher than 3. On an ENEMY the same deal runs the other way: its goal grows a way out that costs 4 minus its stacks, so a badly burned enemy is the cheapest one to be rid of. Burn is bad for whoever is carrying it. And it burns PAPER: every time Burn lands on you there is a 1-in-4 chance that one random scroll in your pack goes up with it. Pills and potions are safe.
- The buffs are felt by enemies only. Marked is a debuff, and a debuff is felt by whoever is carrying it — Marked on YOU doubles every hit you take and goes straight past the shields you were counting on to stop it. Burn's halving is the exception that proves it is a column and not a rule about the word: there is no attack of yours for a halving to sit on, so the sheet says enemies only.

### The ground: tiles and units

Two things can be on a square of the board that are not a body, and they layer — a unit stands on top of a tile effect. Mostly they do not BLOCK anything: an enemy walks in and whatever is there reacts. Wherever an item or a scroll names one, hover the chip under its description to read it.

- **Fire (a tile effect)** — Anything that walks into it, or starts its turn standing in it, takes +1 Burn — and so does anything the fire is lit UNDER, on the spot. A big body pays for every burning square it covers. It burns for 3 GAMES — not turns — wherever it is lit. Scroll of Fire lights the whole front column, Red Candle lights one square you pick in columns 2-3, and Hot Bombs leaves it on every square a bomb went off over.
- **Landmine (a unit)** — Steps on it, and it explodes: no Bomb of yours is spent, but it counts as one, so every bomb relic in your pack reads it — Brimstone widens the blast, Blood Bombs heals you, and Hot Bombs and Sticky Bombs leave a tile in the crater (Fire, and Web that stuns whatever walks in). Like a bomb it destroys rather than defeats, so nothing drops. Landmines lays one after every game you finish.
- **The two together** — Fire and a mine cannot share a square. Whichever arrives second, the heat sets the mine off and the blast blows the fire out.
- **Poops (units that block)** — A WALL. Nothing can step onto one, so an enemy that reaches it spends its step hitting it instead, for exactly what it would hit you for. You can break it too — a bomb, a thrown potion, anything that hits the ground. Broken, it pays out whoever broke it: a Poop drops a piece of loot or lets a fly out, a Golden Poop pays gold, a Rainbow Poop heals you for 3.
- Enemies steer around mines when they have anywhere else to go, and walk straight through them when they don't — a body in the lane is a wall that might never move, a mine is a toll paid once. So a minefield SHAPES where they come at you rather than stopping them.

### Curse goals

A curse goal is a row on your checklist you are trying NOT to complete. Break it and the penalty is always the same one: a random enemy spawns at the run's current difficulty. A curse bills you in the run's own currency rather than reaching for your Health bar.

### Luck

Every point of Luck is a 50% chance of one more roll, and the better result is kept. It compounds rather than adding — at 1 Luck a 25% chance is really 34%, and at 3 Luck it is 50%. It reaches every random decision the run makes: item rarity, chest sizes, shop stock, scrolls, machines — and the chance a lost run stands an enemy up, which Luck pushes DOWN.

Negative Luck is the same machine backwards — a chance of extra rolls, keep the worse. And any odds the game shows you are the odds your Luck will actually roll, not the number on the sheet.

## ⚠ Bosses and difficulty

*The clock you ride, and what rides in on it.*

There are two difficulty axes. The pressure ladder in §2 is the one you steer. This is the one that ticks up on its own.

The tier counts SPAWNS, not games: every time bodies land — arriving at an Enemies or Champion node, or losing with nothing down — is one spawn, and every 4 of them the run's tier goes up: Low, Medium, High, Insane, and there it stops. An Event or a Shop node lands nothing, so routing through them holds the tier where it is. A higher tier means enemies that hit harder — and a bigger board to cross before they reach you, which is the counterweight.

### Where bosses come from

- A CHAMPION node (!!) stands a boss of the current tier, alone.
- Every 4th spawn lands a boss ON TOP of whatever else was arriving — so a lost run can be the one that brings a boss, and a Champion node that is also that spawn brings two.

The count to the next one is on the strip over the board, and the spawn before it is announced in a popup, once.

A boss is a different set of rules:

- A boss's goal is a tighter version of an ordinary one — the true ending, not the ending; deathless, not merely won.
- It hits for 3 to 9, where an ordinary enemy hits for 1 to 4.
- It drops a Boss relic, out of a pool nothing else can reach.
- Bombs do it no damage at all. The goal is the only thing that removes it. You can still throw one — it spends the charge and deals nothing, but what the blast LEAVES still lands, which is how Hot Bombs burns a boss and Sticky Bombs webs one.
- A Champion node cannot be BASHED. Scrambling or transmuting it buys you a DIFFERENT boss, not a way past this one.

> A boss cannot be dashed past either. It follows you like everything else on the board, and only its goal removes it.

### Locations

The run is always SOMEWHERE. It starts in a Low location, and every difficulty up moves it to a new one of the new tier — Burning Basement, The Hive, the Dark Room. You do not choose it: it arrives with a popup of its picture and what it does, and then sits beside the difficulty on the strip over the board. Hover it to read it again; click it to open it.

- Some do something WHEN YOU ENTER — once, with the first game you pick there: bodies of their kind walk on, fire is lit, poops are left on the board. A location dealt in the middle of a game waits for the next one, so nothing lands in a game you are already playing.
- Some change a rule for as long as you are there: damage you take is doubled, or one game on every offering is a free rift.
- Some have a TRADE you can make a few times while you are there — the button is on the location's popup, greyed with the reason when you cannot pay.
- Most LEAN the rolls: things carrying their tag — enemies, bosses, relics, loot — turn up a little more often there. Burning Basement's fire things are 20% likelier.

> A location has no goal and nothing to fail. It lasts until the next difficulty up, and then the run moves on.

## ⟡ Fractures

*Ten harder runs, unlocked one at a time.*

A Fracture is a harder run. There are ten, and each one keeps every Fracture below it: Fracture 6 is Fractures 1 to 6 together. Fracture 0 is the game as it is.

### Unlocking them

- They unlock PER CHARACTER. Win a run as a character to open Fracture 1 for them; win at their highest Fracture to open the next.
- Pick the level on the character select, in the row under the hero. It stays on whatever you picked last for that hero.
- A custom run can be played at any Fracture that hero has unlocked, but it is practice: it unlocks nothing and wins no trophy.

### The ladder

| Fracture | What it adds |
| --- | --- |
| ⟡1 | Every game grants 1 fewer shield (never below 1). |
| ⟡2 | Shops are dearer: everything on a shelf costs 1 more gold. |
| ⟡3 | Every game grants 1 fewer shield (never below 1). |
| ⟡4 | Every arrival brings one more body, bosses included. |
| ⟡5 | Every game grants 1 fewer shield (never below 1). |
| ⟡6 | Difficulty rises a spawn sooner: a boss every 3rd spawn. |
| ⟡7 | The board starts a row taller: more enemies abreast. |
| ⟡8 | Enemies take an extra turn after every game beaten or escaped. |
| ⟡9 | Enemies hit harder: their damage is doubled. |
| ⟡10 | The Collapse: beat the Amulet, then carry it back to the start. |

### What you get for it

- Every repeat win pays 10% more XP per Fracture: 55 at Fracture 1, 100 at Fracture 10, where an ordinary repeat win pays 50.
- A game's 🏆 and a character's 🏆 carry the highest Fracture they were won at.

### Fracture 10: the Collapse

Beating the Amulet does not end the run. You pick it up, every game you played is fractured into one you have not, and the run is won by carrying the Amulet back to the game you started on. Arriving is enough: you do not play it again. The road home is as long as the road out, and everything still on the board comes with you.

> The level you are playing is beside your portrait at the top of the screen. Hover it for everything that level is doing.

## 🛟 When it goes wrong

*Recovery, in the order things actually go wrong.*

Every one of these is a normal Tuesday, not a mistake. This is the chapter to open when a run is going badly.

### I cannot do this goal

Decide BEFORE you travel, while the card is still open. Bash the game if you never want to see it again; Transmute it if you want a different game in the same spot with the road unchanged; Scramble the whole offering if none of the three appeal. Once you travel, the enemy is on the board and only a bomb or the goal itself will move it.

### I already travelled and I still cannot do it

Beat the game anyway. You move on, the enemy follows, and its goal goes on your checklist where you can clear it in some LATER game that happens to suit it. That is not a loss, it is a debt — and debts in this game are payable in any currency.

### I keep losing runs of this game

Each lost run hands the board a turn, and the board is closer every time. After 3 lost runs (1 at a Traditional game) Escape opens: it pays no chest and costs at least two enemies unless you beat a goal here, but it stops the bleeding, and every goal stays on your checklist to clear somewhere friendlier.

And beat ONE body's goal if you possibly can — any goal on the list. A game that ends with no goal beaten stands one more enemy up.

### I have four followers and they are killing me

In rough order of what to try:

- ROUTE AWAY from the Amulet. Getting back to five or more hops means a game you finish with a body down stands nobody new up. That is the biggest single lever in the game and it costs only games.
- Pick cards whose games can pay off SEVERAL old goals at once. Read the checklist first and choose the game to fit it, rather than the other way round.
- Clear an old goal even if you cannot beat this game — it kills that follower on the spot, wherever it is standing.
- Bomb the ordinary enemies. No drop and no gold, but a dead enemy is a dead enemy.
- Push the front-line body backwards to buy a turn, or sideways to unjam a lane.
- Clear a game first try. Nothing you never lost is a turn the stack never took, and the whole shield pool is still standing when you report — a stack that cannot reach your Health is a stack you can outlast.

### The offering is all dead ends

Dash is a total select — it ignores the offering and lets you move to any connected game at all. It is the right answer to a bad table far more often than people spend it.

### I want to stop

Save and quit from the menu. Nothing decays, nothing expires, and the run will be exactly where you left it. You are meant to be away playing something else — that is the game.

## ◎ Where every number is

*A map of the screen. Nothing is drawn twice.*

There is no HUD strip. Every number is drawn once, by whatever owns it, which takes a moment to learn and then never gets in the way.

- **Health, shields, statuses** — On the hero, on the left of the board. Hearts under the portrait, one shield over it per shield you have — the ones that stay nearest your face, the Temporary ones after them with a clock on them. Anything wearing that clock is going away, statuses included.
- **Gold** — A chip in the top bar.
- **Difficulty and location** — The first line of the DIFFICULTY strip over the board: the tier (Low to Insane) with its four pips, and the location you are in on the right — hover it, or click it.
- **Amulet pressure** — The second line of the DIFFICULTY strip: how many spawns until the next difficulty up, how far the Amulet is and the pressure that puts on you (its two pips, in the band's colour — empty out in the wilds), and on the right what ending THIS game will stand up (☠ +N when this game ends). The strip takes the band's colour.
- **What kind of place a game is** — Its mark — ! ? !! $ — on the card, on the 🗺 map and on the route ladder.
- **Push and Bomb charges** — On their own buttons, on the board's toolbar.
- **Bash, Dash, Transmute, Scramble** — Chips on the row under the offering. Dash and Scramble act at once; Bash and Transmute ARM, and the next card you click is the one they hit.
- **Shields a game would grant** — On the offering's hover line, and in full on the card.
- **What is waiting at a game** — Hover its cover: the enemy's picture and its goal, on one line under the offering.
- **Anything else on the page** — Hover it. An enemy, a status, a relic and the enemy-turns readout each show a small card — the short version of what clicking them opens.
- **Where you have been** — The strip across the top: every game you have played, in order, with a dashed arrow to the Amulet.
- **What you owe** — The checklist, left column.
- **What is chasing you** — The board, right column.

### Elsewhere in the menus

- **→ Optimal Path** — The shortest road from where you stand to the Amulet, rung by rung, with every node's kind marked. It lives in the offering's heading row, and on every offered card — a card's own button routes the path as it would be if you took it.
- **🗺 Map** — The star chart, with the road ahead drawn over it. It lives in the header, so it opens from anywhere in a run.
- **✦ Atlas** — The same star chart opened from the menus, with no run on it. Not a run tool — a thing to look at.
- **Collection** — Every item, scroll, enemy, event and status in the game, and whether you have met it.
- **🏆 Tier List** — Your own ranking of every game you have beaten, across all runs, with the notes you wrote at the time.
- **⚙ Custom Run** — Build a run out of a chosen slice of the catalog — which games can be on the map, which can start it, which can be the Amulet, and how long the road is.
