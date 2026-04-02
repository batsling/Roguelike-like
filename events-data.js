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
 *   { type:'heal',       value: N }                  — restore N HP
 *   { type:'damage',     value: N }                  — take N damage
 *   { type:'gold',       value: N }                  — gain/lose gold (negative = lose)
 *   { type:'curse',      value:'random'|curseName }  — gain a curse
 *   { type:'combat_status', status:'frail'|etc, stacks: N } — start combat debuffed
 *   { type:'none' }                                  — no effect (narrative only)
 */

var EVENTS_DATA = [

  // ─────────────────────────────────────────────────
  //  1. THE WANDERING MONK
  // ─────────────────────────────────────────────────
  {
    id: 'wandering_monk',
    name: 'The Wandering Monk',
    description: 'A robed figure sits cross-legged in the middle of the path, eyes closed. He doesn\'t seem to notice you — or perhaps he simply doesn\'t care.',
    choices: [
      {
        id: 'monk_speak',
        text: 'Speak to him',
        type: 'stat_check',
        stat: 'charisma',
        rollDescription: 'You attempt to engage the monk in conversation...',
        outcomes: {
          crit_bad: {
            description: 'The monk\'s eyes snap open. He mutters a curse and disappears in a puff of incense smoke — but not before the curse takes hold of you.',
            effects: [{ type: 'curse', value: 'random' }],
            next: null
          },
          bad: {
            description: 'The monk ignores you completely. You stand there awkwardly for a moment before giving up.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'The monk opens one eye and smiles faintly. He offers you a small blessing before returning to meditation.',
            effects: [{ type: 'heal', value: 8 }],
            next: null
          },
          crit_good: {
            description: 'The monk rises and bows deeply. He speaks at length about inner peace — and then, with a wave of his hand, lifts one of your curses.',
            effects: [{ type: 'remove_curse', value: 'random' }],
            next: null
          }
        }
      },
      {
        id: 'monk_rob',
        text: 'Search his robe for valuables',
        type: 'stat_check',
        stat: 'dexterity',
        rollDescription: 'You quietly reach toward his robes...',
        outcomes: {
          crit_bad: {
            description: 'The monk grabs your wrist without opening his eyes. He curses you for your greed and shoves you away.',
            effects: [{ type: 'curse', value: 'Curse of Greed I' }, { type: 'damage', value: 5 }],
            next: null
          },
          bad: {
            description: 'You find only lint. The monk doesn\'t stir, but you feel vaguely judged.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'A small pouch of coins falls from his sleeve. He still doesn\'t move.',
            effects: [{ type: 'gold', value: 15 }],
            next: null
          },
          crit_good: {
            description: 'You find a hidden compartment containing gold and a curious ward stone. The monk exhales slowly — he knew, and he let you take it.',
            effects: [{ type: 'gold', value: 25 }, { type: 'heal', value: 5 }],
            next: null
          }
        }
      },
      {
        id: 'monk_pass',
        text: 'Step around him and move on',
        type: 'simple',
        outcome: {
          description: 'You give the monk a wide berth. As you pass, he says quietly: "Wisdom is knowing when not to act." You\'re not sure if that\'s a compliment.',
          effects: [{ type: 'none' }],
          next: null
        }
      }
    ]
  },

  // ─────────────────────────────────────────────────
  //  2. THE ABANDONED CACHE
  // ─────────────────────────────────────────────────
  {
    id: 'abandoned_cache',
    name: 'Abandoned Cache',
    description: 'A rusted military footlocker sits half-buried in rubble, lid slightly ajar. Whatever was here, someone left in a hurry.',
    choices: [
      {
        id: 'cache_pry',
        text: 'Force it open',
        type: 'stat_check',
        stat: 'strength',
        rollDescription: 'You plant your feet and heave against the warped lid...',
        outcomes: {
          crit_bad: {
            description: 'The lid gives way violently and a spring-loaded trap launches straight into your face. The contents are ruined.',
            effects: [{ type: 'damage', value: 8 }],
            next: null
          },
          bad: {
            description: 'You wrench it open after a struggle. The inside has been picked clean — just mold and torn cloth.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'The lid swings open cleanly. A small collection of supplies is still intact.',
            effects: [{ type: 'heal', value: 5 }, { type: 'gold', value: 10 }],
            next: null
          },
          crit_good: {
            description: 'The chest flies open to reveal a cache of valuables left by someone who didn\'t make it back.',
            effects: [{ type: 'gold', value: 30 }, { type: 'item', value: 'random' }],
            next: null
          }
        }
      },
      {
        id: 'cache_pick',
        text: 'Pick the lock carefully',
        type: 'stat_check',
        stat: 'dexterity',
        rollDescription: 'You kneel down and work at the mechanism with delicate precision...',
        outcomes: {
          crit_bad: {
            description: 'A needle trap fires from the lock. The poison is mild but your hands are shaking now.',
            effects: [{ type: 'damage', value: 4 }, { type: 'combat_status', status: 'frail', stacks: 2 }],
            next: null
          },
          bad: {
            description: 'You get the lock open eventually, but you broke a pick doing it. The chest is empty.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'Click. The lock surrenders to your skill. You find some salvageable goods inside.',
            effects: [{ type: 'gold', value: 15 }],
            next: null
          },
          crit_good: {
            description: 'The lock mechanism practically sings as you coax it open. Inside: untouched loot and a note that reads "For whoever is skilled enough to find this."',
            effects: [{ type: 'gold', value: 20 }, { type: 'item', value: 'random' }],
            next: null
          }
        }
      },
      {
        id: 'cache_examine',
        text: 'Examine it carefully before touching it',
        type: 'stat_check',
        stat: 'intelligence',
        rollDescription: 'You study the chest, looking for traps or identifying marks...',
        outcomes: {
          crit_bad: {
            description: 'You\'re so busy analyzing that you accidentally trigger the trap while leaning in to get a closer look.',
            effects: [{ type: 'damage', value: 6 }],
            next: null
          },
          bad: {
            description: 'Nothing immediately obvious. You open it cautiously and find it\'s been empty for a long time.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'You spot the pressure plate inside and disarm it easily. The supplies underneath are in good condition.',
            effects: [{ type: 'heal', value: 6 }, { type: 'gold', value: 10 }],
            next: null
          },
          crit_good: {
            description: 'You identify military markings indicating this was an officer\'s personal cache. You know exactly what to expect inside — and none of it is a trap.',
            effects: [{ type: 'gold', value: 25 }, { type: 'item', value: 'random' }, { type: 'heal', value: 5 }],
            next: null
          }
        }
      }
    ]
  },

  // ─────────────────────────────────────────────────
  //  3. THE DESPERATE MERCHANT
  // ─────────────────────────────────────────────────
  {
    id: 'desperate_merchant',
    name: 'The Desperate Merchant',
    description: 'A haggard merchant waves you down from behind an overturned cart. His wares are scattered across the road. "Please — I\'ll make you a deal, just help me out here."',
    choices: [
      {
        id: 'merchant_help',
        text: 'Help him gather his goods',
        type: 'stat_check',
        stat: 'charisma',
        rollDescription: 'You lend a hand, and the two of you get talking...',
        outcomes: {
          crit_bad: {
            description: 'While you\'re distracted helping, he takes the opportunity to swipe something from your pack. You don\'t notice until he\'s gone.',
            effects: [{ type: 'gold', value: -20 }, { type: 'curse', value: 'random' }],
            next: null
          },
          bad: {
            description: 'He thanks you briefly, packs up, and hurries off with barely a word. You get nothing for your trouble.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'He\'s grateful and sells you something at a discount before heading off.',
            effects: [{ type: 'gold', value: -5 }, { type: 'item', value: 'random' }],
            next: null
          },
          crit_good: {
            description: 'By the time you\'re done, he\'s practically weeping with gratitude. He insists you take a gift, free of charge.',
            effects: [{ type: 'item', value: 'random' }, { type: 'gold', value: 10 }],
            next: null
          }
        }
      },
      {
        id: 'merchant_buy',
        text: 'Offer to buy something from him (costs 15 Gold)',
        requires: { gold: 15 },
        type: 'simple',
        outcome: {
          description: 'He lights up immediately. "You\'re a lifesaver!" He gives you a deal on whatever he can scrounge together.',
          effects: [{ type: 'gold', value: -15 }, { type: 'item', value: 'random' }],
          next: null
        }
      },
      {
        id: 'merchant_extort',
        text: 'Demand he pay you for your silence — you could just rob him',
        type: 'stat_check',
        stat: 'strength',
        rollDescription: 'You loom over him with your best menacing expression...',
        outcomes: {
          crit_bad: {
            description: 'He pulls a crossbow from under the cart. "I\'ve dealt with worse than you." You back off — badly rattled.',
            effects: [{ type: 'damage', value: 10 }, { type: 'curse', value: 'Curse of Guilt I' }],
            next: null
          },
          bad: {
            description: 'He just stares at you, unimpressed. "I have nothing left to give." You feel like an idiot.',
            effects: [{ type: 'curse', value: 'Curse of Guilt I' }],
            next: null
          },
          good: {
            description: 'He hands over his coin purse with trembling hands. You feel terrible about it, but gold is gold.',
            effects: [{ type: 'gold', value: 20 }, { type: 'curse', value: 'Curse of Guilt I' }],
            next: null
          },
          crit_good: {
            description: 'He practically throws his savings at you and runs. You find more than expected in the purse.',
            effects: [{ type: 'gold', value: 35 }, { type: 'curse', value: 'Curse of Guilt II' }],
            next: null
          }
        }
      },
      {
        id: 'merchant_leave',
        text: 'Walk past without stopping',
        type: 'simple',
        outcome: {
          description: 'His pleas fade behind you as you keep moving. Someone else\'s problem.',
          effects: [{ type: 'none' }],
          next: null
        }
      }
    ]
  },

  // ─────────────────────────────────────────────────
  //  4. THE COLLAPSED SHRINE
  // ─────────────────────────────────────────────────
  {
    id: 'collapsed_shrine',
    name: 'Collapsed Shrine',
    description: 'The remnants of a small roadside shrine have toppled over. The idol inside is cracked but intact — something about it still feels charged with power.',
    choices: [
      {
        id: 'shrine_pray',
        text: 'Pray at the shrine',
        type: 'stat_check',
        stat: 'charisma',
        rollDescription: 'You kneel and offer a sincere prayer...',
        outcomes: {
          crit_bad: {
            description: 'Whatever listened does not approve of you. A cold dread settles over you that won\'t shake loose.',
            effects: [{ type: 'curse', value: 'random' }, { type: 'damage', value: 3 }],
            next: null
          },
          bad: {
            description: 'Nothing answers. The idol stares at you blankly. You feel slightly foolish.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'A warmth spreads through your chest. Whatever gods watch this place are satisfied for now.',
            effects: [{ type: 'heal', value: 10 }],
            next: null
          },
          crit_good: {
            description: 'The idol glows faintly. You feel a burden lifted — your faith was genuine enough to break something that was weighing you down.',
            effects: [{ type: 'heal', value: 15 }, { type: 'remove_curse', value: 'random' }],
            next: null
          }
        }
      },
      {
        id: 'shrine_study',
        text: 'Study the runes on the idol',
        type: 'stat_check',
        stat: 'intelligence',
        rollDescription: 'You lean in and trace the inscriptions with your eyes...',
        outcomes: {
          crit_bad: {
            description: 'You mispronounce one of the inscribed words aloud without thinking. The idol shudders and a wave of misfortune rolls over you.',
            effects: [{ type: 'curse', value: 'Curse of Misfortune II' }],
            next: null
          },
          bad: {
            description: 'The runes are too worn to read. An old dialect you don\'t recognize.',
            effects: [{ type: 'none' }],
            next: null
          },
          good: {
            description: 'You piece together enough to understand it\'s a ward against harm. You feel slightly more resilient.',
            effects: [{ type: 'heal', value: 6 }],
            next: null
          },
          crit_good: {
            description: 'You fully decode the inscription — it\'s a blessing formula. You repeat it correctly and feel your body reinforce itself.',
            effects: [{ type: 'heal', value: 12 }, { type: 'combat_status', status: 'fortified', stacks: 3 }],
            next: null
          }
        }
      },
      {
        id: 'shrine_take',
        text: 'Pocket the idol — it looks valuable',
        type: 'stat_check',
        stat: 'dexterity',
        rollDescription: 'You reach out and grab the idol...',
        outcomes: {
          crit_bad: {
            description: 'As your fingers close around it, a jolt of spiritual backlash surges through your arm. The idol crumbles to dust — taking something of yours with it.',
            effects: [{ type: 'curse', value: 'random' }, { type: 'damage', value: 8 }],
            next: null
          },
          bad: {
            description: 'You pocket it, but immediately feel a creeping unease. You\'ll probably sell it fast.',
            effects: [{ type: 'gold', value: 5 }, { type: 'curse', value: 'Curse of Guilt I' }],
            next: null
          },
          good: {
            description: 'The idol slots into your pack without incident. Could be worth something.',
            effects: [{ type: 'gold', value: 20 }],
            next: null
          },
          crit_good: {
            description: 'The idol seems almost willing to be taken. As you lift it, a compartment in the base pops open, revealing a small gem.',
            effects: [{ type: 'gold', value: 30 }, { type: 'item', value: 'random' }],
            next: null
          }
        }
      },
      {
        id: 'shrine_restore',
        text: 'Try to prop the shrine back up',
        type: 'simple',
        outcome: {
          description: 'It takes some effort, but you set the idol upright and clear the debris. Whatever watches this place seems content. You feel like you did something right.',
          effects: [{ type: 'heal', value: 5 }],
          next: null
        }
      }
    ]
  },

  // ─────────────────────────────────────────────────
  //  5. THE STORM DRAIN
  // ─────────────────────────────────────────────────
  {
    id: 'storm_drain',
    name: 'The Storm Drain',
    description: 'A large storm grate in the road is rattling violently — something is pushing against it from below. You can hear splashing and the unmistakable sound of something trying to get out.',
    choices: [
      {
        id: 'drain_hold',
        text: 'Hold the grate shut',
        type: 'stat_check',
        stat: 'strength',
        rollDescription: 'You plant your boots and push down with everything you have...',
        outcomes: {
          crit_bad: {
            description: 'Whatever it was bursts through and knocks you sprawling. You\'re covered in sewer water and worse — and deeply rattled.',
            effects: [{ type: 'damage', value: 12 }, { type: 'combat_status', status: 'frail', stacks: 3 }],
            next: null
          },
          bad: {
            description: 'You hold it long enough that whatever was trying to escape gives up. You\'re exhausted and soaked.',
            effects: [{ type: 'damage', value: 4 }],
            next: null
          },
          good: {
            description: 'The grate holds. After a while the noise stops. Something down there decided not to bother. You feel stronger for having held it.',
            effects: [{ type: 'heal', value: 4 }],
            next: null
          },
          crit_good: {
            description: 'You not only hold the grate, you jam it shut with nearby rubble. In the sudden quiet, you notice a satchel caught on the grate\'s edge.',
            effects: [{ type: 'gold', value: 15 }, { type: 'heal', value: 8 }],
            next: null
          }
        }
      },
      {
        id: 'drain_open',
        text: 'Open the grate and see what comes out',
        type: 'stat_check',
        stat: 'dexterity',
        rollDescription: 'You yank the grate open and leap back, ready...',
        outcomes: {
          crit_bad: {
            description: 'A writhing mass of something unidentifiable launches itself at you. It\'s not dangerous — just disgusting — but it latches on and won\'t let go without a fight.',
            effects: [{ type: 'damage', value: 6 }, { type: 'curse', value: 'random' }],
            next: null
          },
          bad: {
            description: 'A torrent of foul water and debris washes out, soaking you. Whatever it was escaped into the shadows.',
            effects: [{ type: 'damage', value: 3 }],
            next: null
          },
          good: {
            description: 'A small creature — battered but alive — squeezes out and scurries off. You saved it. It drops something as it goes.',
            effects: [{ type: 'gold', value: 10 }],
            next: null
          },
          crit_good: {
            description: 'A familiar-looking creature tumbles out and looks up at you with enormous grateful eyes. It presses a coin into your palm and disappears before you can blink.',
            effects: [{ type: 'gold', value: 25 }, { type: 'heal', value: 8 }],
            next: null
          }
        }
      },
      {
        id: 'drain_leave',
        text: 'Walk away quickly',
        type: 'simple',
        outcome: {
          description: 'Not your problem. You walk faster and try not to think about what you heard. The rattling fades into the distance.',
          effects: [{ type: 'none' }],
          next: null
        }
      }
    ]
  }

];
