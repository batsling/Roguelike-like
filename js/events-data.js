/**
 * EVENTS-DATA.JS
 * Definitions for all pre-combat events.
 * Each event uses the two-roll D20 system (success check + criticality check).
 *
 * Effect types:
 *   { type: 'heal',            value: N }
 *   { type: 'damage',          value: N }
 *   { type: 'gold',            value: N }
 *   { type: 'gold_range',      min: N, max: N }
 *   { type: 'item_tagged',     tag: 'coin'|'eye'|... }
 *   { type: 'curse',           value: 'Curse Name' }
 *   { type: 'curse_difficulty',curseBase: 'Curse of ...' }
 *   { type: 'combat_status',   status: 'fear'|'blind'|..., stacks: N }
 *   { type: 'combat_flag',     flag: 'ambush'|'ambushed' }
 *   { type: 'none' }
 *
 * {name} in description strings is replaced with the player character's name.
 */

var EVENTS_DATA = [
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
  }
];
