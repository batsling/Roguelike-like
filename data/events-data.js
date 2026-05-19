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
 *   description: string  — opening flavor text (supports {name} and {storedCard})
 *   image: string        — path to event image (required to appear in event pool)
 *   game: string         — optional source game name
 *   choices: Choice[]    — top-level choices
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
 *   Shows the outcome directly with no dice roll. Blue left border.
 *   outcome: Outcome
 *
 *   — stat_check —
 *   Triggers the two-roll D20 system. Orange left border.
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
 *                               (supports {name} and {storedCard} placeholders)
 *   effects: Effect[]
 *   next: string | null       — node id to branch into, or null (= end event)
 * }
 *
 * Description Placeholders:
 *   {name}        — replaced with the player character's name
 *   {storedCard}  — replaced with the name of the card stored in gameState.noteForYourselfCard
 *                   (defaults to 'Iron Wave' on first encounter)
 *
 * Effect:
 *   { type:'heal',              value: N }
 *   { type:'heal_percent',      value: N }              — heal N% of max HP
 *   { type:'damage',            value: N }
 *   { type:'gold',              value: N }
 *   { type:'gold_range',        min: N, max: N }
 *   { type:'item_tagged',       tag: string }
 *   { type:'curse',             value:'random'|curseName }
 *   { type:'curse_difficulty',  curseBase: string }
 *   { type:'combat_status',     status: string, stacks: N }
 *   { type:'combat_flag',       flag:'ambush'|'ambushed' }
 *   { type:'spawn_enemies',     enemy: string, min: N, max: N }
 *   { type:'note_for_yourself', defaultCard: string }
 *     — Retrieves the card stored in gameState.noteForYourselfCard (or defaultCard on first
 *       encounter) and adds it to the player's run deck. Then opens a card-picker screen
 *       where the player must select a card from their collected deck to store for next time.
 *       Use in a 'simple' choice outcome. The outcome description supports {storedCard} to
 *       show the retrieved card's name in the flavour text.
 *   { type:'none' }
 */

const EVENTS_DATA = [

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
            description: '{name} moves its face close to the hole and peers inside\u2026 {name} howls in pain as something sharp from within the hole lashes out and stabs its eye! Get an Eye Item.',
            effects: [
              { type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' },
              { type: 'item_tagged', tag: 'eye' }
            ]
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
            description: '{name} reaches into the dark hole with its arm to swat at the eyes, but pokes themself in the face on the sharp edges of the hole instead! Get an Eye Item.',
            effects: [
              { type: 'curse_difficulty', curseBase: 'Curse of Ocular Trauma' },
              { type: 'item_tagged', tag: 'eye' }
            ]
          }
        }
      }
    ]
  },

  // ─────────────────────────────────────────────────────────────────────────────
  //  A NOTE FOR YOURSELF
  // ─────────────────────────────────────────────────────────────────────────────
  {
    id: 'note_for_yourself',
    name: 'A Note For Yourself',
    image: 'images/events/ANoteForYourself.png',
    description: 'You spot a loose brick within a pillar that catches your eye.',
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
  },

  // ─────────────────────────────────────────────────────────────────────────────
  //  FRUIT BASKET
  // ─────────────────────────────────────────────────────────────────────────────
  {
    id: 'fruit_basket',
    name: 'Fruit Basket',
    image: 'images/events/FruitBasket.png',
    description: '{name} discovers a basket of fruit. The warm smell of fresh citrus and bananas lingers in the air. A refreshing reprieve!',
    game: 'Mewgenics',
    choices: [
      {
        id: 'fruit_eat',
        text: 'Eat',
        type: 'stat_check',
        stat: 'constitution',
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
  },

  // ─────────────────────────────────────────────────────────────────────────────
  //  THE SSSSSERPENT
  // ─────────────────────────────────────────────────────────────────────────────
  {
    id: 'the_ssssserpent',
    name: 'The Ssssserpent',
    image: 'images/events/TheSsssserpent.png',
    game: 'Slay the Spire',
    description: 'You walk into a room to find a large hole in the ground. As you approach the hole, an enormous serpent creature appears from within. Serpent: "Ho hooo! Hello hello! what have we got here? Hello adventurer, I ask a simple question." Serpent: "The most fulfilling of lives is that in which you can buy anything!" Serpent: "Do you agree?"',
    choices: [
      {
        id: 'serpent_agree',
        text: 'Agree',
        type: 'simple',
        outcome: {
          description: 'Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a stream of gold upwards! It is amazing and terrifying simultaneously. You gather all the gold, thank the snake, and get going.',
          effects: [
            { type: 'gold', value: 100 },
            { type: 'curse', value: 'Curse of Greed II' }
          ]
        }
      },
      {
        id: 'serpent_charm',
        text: 'Charm',
        type: 'stat_check',
        stat: 'charisma',
        rollDescription: 'You flash a winning smile at the serpent...',
        outcomes: {
          crit_good: {
            description: 'Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a stream of gold upwards! It is amazing and terrifying simultaneously. You gather all the gold, thank the snake, and get going.',
            effects: [
              { type: 'gold', value: 150 },
              { type: 'curse', value: 'Curse of Greed I' }
            ]
          },
          good: {
            description: 'Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a stream of gold upwards! It is amazing and terrifying simultaneously. You gather all the gold, thank the snake, and get going.',
            effects: [
              { type: 'gold', value: 125 },
              { type: 'curse', value: 'Curse of Greed II' }
            ]
          },
          bad: {
            description: 'Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a stream of gold upwards! It is amazing and terrifying simultaneously. You gather all the gold, thank the snake, and get going.',
            effects: [
              { type: 'gold', value: 75 },
              { type: 'curse', value: 'Curse of Greed III' }
            ]
          },
          crit_bad: {
            description: 'Serpent: "Yeeeeeeessssssssssessss" Serpent: "Thisss will all be worthhh it." Serpent: "..ssSSs..... ss... sssss....!" The serpent rears its head and blasts a stream of gold upwards! It is amazing and terrifying simultaneously. You gather all the gold, thank the snake, and get going.',
            effects: [
              { type: 'gold', value: 50 },
              { type: 'curse', value: 'Curse of Greed III' }
            ]
          }
        }
      },
      {
        id: 'serpent_disagree',
        text: 'Disagree',
        type: 'simple',
        outcome: {
          description: 'The serpent stares at you with a look of extreme disappointment.',
          effects: [{ type: 'none' }]
        }
      }
    ]
  }

];

if (typeof window !== 'undefined') window.EVENTS_DATA = EVENTS_DATA;
