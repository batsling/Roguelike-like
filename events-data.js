/**
 * EVENTS-DATA.JS
 *
 * Pre-combat events triggered on combat encounter spaces.
 * Each event shows nested choices, optional stat checks with 4 outcomes,
 * and always leads to combat afterward.
 *
 * FORMAT:
 * {
 *   id: string           — unique identifier
 *   name: string         — display name
 *   description: string  — opening flavor text
 *   choices: Choice[]    — top-level choices
 *   nodes: {}            — optional sub-nodes keyed by id (for nested paths)
 * }
 *
 * Choice:
 * {
 *   id: string
 *   text: string                  — button label
 *   requires: { gold: N }         — optional (hide if not met)
 *   type: 'simple' | 'stat_check'
 *
 *   — simple —
 *   outcome: Outcome
 *
 *   — stat_check —
 *   stat: 'strength'|'dexterity'|'intelligence'|'charisma'
 *   rollDescription: string       — flavor shown before roll
 *   outcomes: {
 *     crit_bad: Outcome
 *     bad:      Outcome
 *     good:     Outcome
 *     crit_good:Outcome
 *   }
 * }
 *
 * Outcome:
 * {
 *   description: string       — flavor text shown after choice / roll
 *   effects: Effect[]
 *   next: string | null       — node id to branch into, or null (= end event)
 * }
 *
 * Effect:
 *   { type:'heal',            value: N }
 *   { type:'heal_percent',    value: N }          — heal N% of max HP
 *   { type:'damage',          value: N }
 *   { type:'gold',            value: N }
 *   { type:'gold_range',      min: N, max: N }
 *   { type:'item_tagged',     tag: string }
 *   { type:'curse',           value:'random'|curseName }
 *   { type:'curse_difficulty',curseBase: string }
 *   { type:'combat_status',   status: string, stacks: N }
 *   { type:'combat_flag',     flag:'ambush'|'ambushed' }
 *   { type:'spawn_enemies',   enemy: string, min: N, max: N }
 *   { type:'none' }
 */

var EVENTS_DATA = [

  // ─────────────────────────────────────────────────────────────────────────────
  //  WATCHING EYEBALLS
  // ─────────────────────────────────────────────────────────────────────────────
  {
    id: 'watching_eyeballs',
    name: 'Watching Eyeballs',
    description: '{name} stumbles upon a dark hole. Numerous eyes peer out from the darkness.',
    image: 'images/events/WatchingEyeballs.png',
    game: 'Mewgenics',
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
            description: 'The eyes glare directly at {name} as {name} attempts to sneak by\u2026 {name} bolts into a sprint in order to get away as quickly as possible!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 1 }]
          },
          crit_bad: {
            description: '{name} approaches the crack in the wall, trying to discern what creature\'s eyes are staring at it\u2026 The unnerving gaze of the eyeballs terrifies {name}, and they run for their life, right into an ambush!',
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
            description: 'After closer examination, {name} discovers it was just a trick of the light\u2026 The eyes were coins!',
            effects: [{ type: 'gold_range', min: 10, max: 20 }]
          },
          bad: {
            description: '{name} looks directly at the eyes, no one wanting to move first. Their eyes begin to water in pain as they resist the urge to blink. {name} doesn\'t say anything and turns and runs in terror!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 2 }]
          },
          crit_bad: {
            description: '{name} moves its face close to the hole and peers inside\u2026 {name} howls in pain as something sharp from within the hole lashes out and stabs its eye!',
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

  // ─────────────────────────────────────────────────────────────────────────────
  //  FRUIT BASKET
  // ─────────────────────────────────────────────────────────────────────────────
  {
    id: 'fruit_basket',
    name: 'Fruit Basket',
    image: 'images/events/WatchingEyeballs.png',
    description: '{name} discovers a basket of fruit. The warm smell of fresh citrus and bananas lingers in the air. A refreshing reprieve!',
    game: 'Mewgenics',
    choices: [
      {
        id: 'fruit_eat',
        text: 'Eat',
        type: 'stat_check',
        stat: 'charisma',
        rollDescription: '{name} reaches for the fruit...',
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
            description: 'The fruit tastes great, at first... But after {name} devours it, they look down and notice that the remains are all rotted. {name} begins to feel sick as poison sets in...',
            effects: [{ type: 'combat_status', status: 'poison', stacks: 4 }]
          }
        }
      },
      {
        id: 'fruit_destroy',
        text: 'Destroy',
        type: 'stat_check',
        stat: 'strength',
        rollDescription: '{name} rears back to destroy the fruit...',
        outcomes: {
          crit_good: {
            description: '{name} tears open the fruit and pokes through the remains, looking for something useful...',
            effects: [{ type: 'item_tagged', tag: 'seed' }]
          },
          good: {
            description: '{name} crushes the fruit, spraying juice everywhere. It smells nice but nothing happens...',
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
        id: 'fruit_examine',
        text: 'Examine',
        type: 'stat_check',
        stat: 'intelligence',
        rollDescription: '{name} leans in to examine the basket closely...',
        outcomes: {
          crit_good: {
            description: 'Upon closer inspection, {name} notices that the fruit is shimmering in the dim light. {name} carefully bites into the ripe fruit... It\'s the most delicious thing they\'ve ever tasted!',
            effects: [{ type: 'heal', value: 15 }, { type: 'combat_status', status: 'buffer', stacks: 1 }]
          },
          good: {
            description: '{name} examines the fruit in the basket and finds one that looks fresh.',
            effects: [{ type: 'heal', value: 5 }]
          },
          bad: {
            description: 'As {name} was examining the fruit, {name} was not paying attention to its surroundings... It\'s a trap!',
            effects: [{ type: 'combat_flag', flag: 'ambushed' }]
          },
          crit_bad: {
            description: '{name} picks up one of the strange fruits, and it rots in its hands! {name} jumps back in fear as the whole basket begins to rapidly decompose!',
            effects: [{ type: 'combat_status', status: 'fear', stacks: 5 }]
          }
        }
      }
    ]
  }

];
