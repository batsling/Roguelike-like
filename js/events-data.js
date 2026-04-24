/**
 * EVENTS-DATA.JS
 * Definitions for all pre-combat events.
 * Each event uses the two-roll D20 system (success check + criticality check).
 *
 * Effect types:
 *   { type: 'heal',            value: N }
 *   { type: 'heal_percent',    value: N }        — N% of max HP
 *   { type: 'damage',          value: N }
 *   { type: 'gold',            value: N }
 *   { type: 'gold_range',      min: N, max: N }
 *   { type: 'item_tagged',     tag: 'coin'|'eye'|'seed'|... }
 *   { type: 'curse',           value: 'Curse Name' }
 *   { type: 'curse_difficulty',curseBase: 'Curse of ...' }
 *   { type: 'combat_status',   status: 'fear'|'blind'|'poison'|'buffer'|..., stacks: N }
 *   { type: 'combat_flag',     flag: 'ambush'|'ambushed' }
 *   { type: 'spawn_enemies',   enemy: 'Name', min: N, max: N }
 *   { type: 'note_for_yourself', defaultCard: 'Card Name' }
 *   { type: 'none' }
 *
 * Metadata fields (used by collection screen):
 *   rarity:     'Common' | 'Uncommon' | 'Rare' | 'Legendary'
 *   type:       game genre (e.g. 'Strategy', 'Deckbuilder')
 *   inputs:     string[] — stat checks or resources used
 *   outputs:    string[] — possible outcome categories
 *   tags:       string[] — thematic tags
 *
 * {name} in description strings is replaced with the player character's name.
 * {storedCard} is replaced with the name of the stored Note For Yourself card.
 */

var EVENTS_DATA = [
  // ─── WATCHING EYEBALLS ───────────────────────────────────────────────────────
  {
    id: 'watching_eyeballs',
    name: 'Watching Eyeballs',
    description: '{name} stumbles upon a dark hole. Numerous eyes peer out from the darkness.',
    image: 'images/events/WatchingEyeballs.png',
    game: 'Mewgenics',
    rarity: 'Common',
    type: 'Strategy',
    inputs: ['Dexterity', 'Intelligence', 'Strength'],
    outputs: ['Ambush', 'Fear', 'Item', 'Gold', 'Curse'],
    tags: ['spooky', 'hole'],
    choices: [
      {
        text: 'Sneak By',
        type: 'stat_check',
        stat: 'dexterity',
        outcomes: {
          crit_good: {
            description: '{name} sneaks by the spooky looking crack, getting into a position to ambush!',
            effects: [{ type: 'combat_flag', flag: 'ambush' }]
          },
          good: {
            description: '{name} carefully sneaks by the wall and nothing appears to happen.',
            effects: [{ type: 'none' }]
          },
          bad: {
            description: 'The eyes glare directly at {name} as {name} attempts to sneak by… {name} bolts into a sprint in order to get away as quickly as possible!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 1 }]
          },
          crit_bad: {
            description: '{name} approaches the crack in the wall, trying to discern what creature\'s eyes are staring at it… The unnerving gaze of the eyeballs terrifies {name}, and they run for their life, right into an ambush!',
            effects: [
              { type: 'combat_status', status: 'fear', stacks: 2 },
              { type: 'combat_flag', flag: 'ambushed' }
            ]
          }
        }
      },
      {
        text: 'Examine',
        type: 'stat_check',
        stat: 'intelligence',
        outcomes: {
          crit_good: {
            description: '{name} discovers the scary looking eyes were just large coins, glinting in the dim light!',
            effects: [{ type: 'item_tagged', tag: 'coin' }]
          },
          good: {
            description: 'After closer examination, {name} discovers it was just a trick of the light… The eyes were coins!',
            effects: [{ type: 'gold_range', min: 10, max: 20 }]
          },
          bad: {
            description: '{name} looks directly at the eyes, no one wanting to move first. Their eyes begin to water in pain as they resist the urge to blink. {name} doesn\'t say anything and turns and runs in terror!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 2 }]
          },
          crit_bad: {
            description: '{name} moves its face close to the hole and peers inside… {name} howls in pain as something sharp from within the hole lashes out and stabs its eye!',
            effects: [{ type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' }]
          }
        }
      },
      {
        text: 'Bash',
        type: 'stat_check',
        stat: 'strength',
        outcomes: {
          crit_good: {
            description: '{name} bats at the eyes with lightning fast strikes, dispatching them with ease!',
            effects: [{ type: 'item_tagged', tag: 'eye' }]
          },
          good: {
            description: '{name} smashes the eyes into concave lumps of flesh!',
            effects: [{ type: 'heal', value: 5 }]
          },
          bad: {
            description: '{name} moves closely to strike the eyes, but they suddenly flash with a blinding brightness!',
            effects: [{ type: 'combat_status', status: 'blind', stacks: 4 }]
          },
          crit_bad: {
            description: '{name} reaches into the dark hole with its arm to swat at the eyes, but pokes themself in the face on the sharp edges of the hole instead!',
            effects: [{ type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' }]
          }
        }
      }
    ]
  },

  // ─── FRUIT BASKET ────────────────────────────────────────────────────────────
  {
    id: 'fruit_basket',
    name: 'Fruit Basket',
    description: '{name} discovers a basket of fruit. The warm smell of fresh citrus and bananas lingers in the air. A refreshing reprieve!',
    image: 'images/events/FruitBasket.png',
    game: 'Mewgenics',
    rarity: 'Common',
    type: 'Strategy',
    inputs: ['Charisma', 'Strength', 'Intelligence'],
    outputs: ['Health', 'Poison', 'Item', 'Enemy', 'Buffer', 'Ambushed', 'Fear'],
    tags: ['food'],
    choices: [
      {
        text: 'Eat',
        type: 'stat_check',
        stat: 'charisma',
        outcomes: {
          crit_good: {
            description: 'The fruit is tasty! {name} gobbles up the whole basket.',
            effects: [{ type: 'heal_percent', value: 50 }]
          },
          good: {
            description: 'Warm juice from the fruit runs down their chin as {name} devours the delicious fruit.',
            effects: [{ type: 'heal_percent', value: 20 }]
          },
          bad: {
            description: '{name} bites into a piece of fruit, then spits it out in disgust! It\'s poisoned!',
            effects: [{ type: 'combat_status', status: 'poison', stacks: 3 }]
          },
          crit_bad: {
            description: 'The fruit tastes great, at first… But after {name} devours it, they look down and notice that the remains are all rotted. {name} begins to feel sick as poison sets in…',
            effects: [{ type: 'combat_status', status: 'poison', stacks: 4 }]
          }
        }
      },
      {
        text: 'Destroy',
        type: 'stat_check',
        stat: 'strength',
        outcomes: {
          crit_good: {
            description: '{name} tears open the fruit and pokes through the remains, looking for something useful…',
            effects: [{ type: 'item_tagged', tag: 'seed' }]
          },
          good: {
            description: '{name} crushes the fruit, spraying juice everywhere. It smells nice but nothing happens…',
            effects: [{ type: 'none' }]
          },
          bad: {
            description: '{name} pushes the basket of fruit over and steps on the fruit, squeezing their juices out onto the ground.',
            effects: [{ type: 'none' }]
          },
          crit_bad: {
            description: '{name} smashes the fruit, and a swarm of fruit flies surround {name}!',
            effects: [{ type: 'spawn_enemies', enemy: 'Fly', min: 6, max: 8 }]
          }
        }
      },
      {
        text: 'Examine',
        type: 'stat_check',
        stat: 'intelligence',
        outcomes: {
          crit_good: {
            description: 'Upon closer inspection, {name} notices that the fruit is shimmering in the dim light. {name} carefully bites into the ripe fruit… It\'s the most delicious thing they\'ve ever tasted!',
            effects: [
              { type: 'heal', value: 15 },
              { type: 'combat_status', status: 'buffer', stacks: 1 }
            ]
          },
          good: {
            description: '{name} examines the fruit in the basket and finds one that looks fresh.',
            effects: [{ type: 'heal', value: 5 }]
          },
          bad: {
            description: 'As {name} was examining the fruit, {name} was not paying attention to its surroundings… It\'s a trap!',
            effects: [{ type: 'combat_flag', flag: 'ambushed' }]
          },
          crit_bad: {
            description: '{name} picks up one of the strange fruits, and it rots in its hands! {name} jumps back in fear as the whole basket begins to rapidly decompose!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 5 }]
          }
        }
      }
    ]
  },

  // ─── A NOTE FOR YOURSELF ─────────────────────────────────────────────────────
  {
    id: 'note_for_yourself',
    name: 'A Note For Yourself',
    description: 'You spot a loose brick within a pillar that catches your eye.',
    image: 'images/events/ANoteForYourself.png',
    game: 'Slay the Spire',
    rarity: 'Uncommon',
    type: 'Deckbuilder',
    inputs: ['Card'],
    outputs: ['Card'],
    tags: [],
    choices: [
      {
        text: 'Take and Give',
        type: 'simple',
        outcome: {
          description: 'You find a folded note and {storedCard} inside. It reads "The Heart awaits." This is your handwriting.',
          effects: [{ type: 'note_for_yourself', defaultCard: 'Iron Wave' }]
        }
      },
      {
        text: 'Ignore',
        type: 'simple',
        outcome: {
          description: '"What is going on?"',
          effects: [{ type: 'none' }]
        }
      }
    ]
  }
];
