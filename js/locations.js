// ===== LOCATIONS.JS - Location Data and Management =====
//
// This module handles:
// - Location data organized by difficulty
// - Random location selection based on difficulty
// - Location tracking and display

// Location data from the Excel sheet
const LOCATIONS_DATA = [
  {
    "name": "Keep of the Lead Lord",
    "difficulty": "Easy",
    "game": "Enter the Gungeon",
    "type": "Building",
    "effect": "Guns are 20% more likely to show up"
  },
  {
    "name": "Black Powder Mine",
    "difficulty": "Medium",
    "game": "Enter the Gungeon",
    "type": "Underground",
    "effect": "Guns are 20% more likely to show up"
  },
  {
    "name": "Hollow",
    "difficulty": "Medium",
    "game": "Enter the Gungeon",
    "type": "Icey",
    "effect": "Guns are 20% more likely to show up"
  },
  {
    "name": "Forge",
    "difficulty": "Hard",
    "game": "Enter the Gungeon",
    "type": "Firey",
    "effect": "Guns are 20% more likely to show up"
  },
  {
    "name": "Bullet Hell",
    "difficulty": "Hard",
    "game": "Enter the Gungeon",
    "type": "Undead",
    "effect": "Guns are 20% more likely to show up"
  },
  {
    "name": "Basement",
    "difficulty": "Easy",
    "game": "The Binding of Isaac",
    "type": "Building",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Burning Basement",
    "difficulty": "Easy",
    "game": "The Binding of Isaac",
    "type": "Firey",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Dross",
    "difficulty": "Easy",
    "game": "The Binding of Isaac",
    "type": "Sewage",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Caves",
    "difficulty": "Medium",
    "game": "The Binding of Isaac",
    "type": "Underground",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Flooded Caves",
    "difficulty": "Medium",
    "game": "The Binding of Isaac",
    "type": "Watery",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Necropolis",
    "difficulty": "Medium",
    "game": "The Binding of Isaac",
    "type": "Undead",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Womb",
    "difficulty": "Hard",
    "game": "The Binding of Isaac",
    "type": "Living",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Cathedral",
    "difficulty": "Hard",
    "game": "The Binding of Isaac",
    "type": "Holy",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "The Void",
    "difficulty": "Hard",
    "game": "The Binding of Isaac",
    "type": "Chaos",
    "effect": "All games in this Location have a 10% chance to be Holy, Devilish, or Stinky"
  },
  {
    "name": "Tartarus",
    "difficulty": "Easy",
    "game": "Hades",
    "type": "Undead",
    "effect": "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    "name": "Asphodel",
    "difficulty": "Easy",
    "game": "Hades",
    "type": "Firey",
    "effect": "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    "name": "Elysium",
    "difficulty": "Medium",
    "game": "Hades",
    "type": "Watery",
    "effect": "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    "name": "Chaos",
    "difficulty": "Medium",
    "game": "Hades",
    "type": "Chaos",
    "effect": "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    "name": "Temple of Styx",
    "difficulty": "Hard",
    "game": "Hades",
    "type": "Building",
    "effect": "When the player enters this location, they will chose one of 3 Gods which will Give the player a it's Boon Item"
  },
  {
    "name": "Titanic Plains",
    "difficulty": "Easy",
    "game": "Risk of Rain 2",
    "type": "General",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Abandoned Aqueduct",
    "difficulty": "Easy",
    "game": "Risk of Rain 2",
    "type": "Desert",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Siphoned Forest",
    "difficulty": "Easy",
    "game": "Risk of Rain 2",
    "type": "Icey",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Wetland Aspect",
    "difficulty": "Easy",
    "game": "Risk of Rain 2",
    "type": "Swampy",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Rallypoint Delta",
    "difficulty": "Medium",
    "game": "Risk of Rain 2",
    "type": "Icey",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Abyssal Depths",
    "difficulty": "Medium",
    "game": "Risk of Rain 2",
    "type": "Firey",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Sundered Grove",
    "difficulty": "Medium",
    "game": "Risk of Rain 2",
    "type": "General",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Sulfur Pools",
    "difficulty": "Medium",
    "game": "Risk of Rain 2",
    "type": "Poisonous",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Sky Meadow",
    "difficulty": "Hard",
    "game": "Risk of Rain 2",
    "type": "Sky",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  },
  {
    "name": "Commencement",
    "difficulty": "Hard",
    "game": "Risk of Rain 2",
    "type": "Lunar",
    "effect": "The Difficulty level has a 50% chance to increase by +1 after beating a game, but whenever a player beats a game, they can open an extra chest for 10 Gold"
  }
];

// Organize locations by difficulty
const locationsByDifficulty = {
  easy: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Easy'),
  medium: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Medium'),
  hard: LOCATIONS_DATA.filter(loc => loc.difficulty === 'Hard')
};

// Get a random location based on difficulty
function getRandomLocation(difficulty) {
  const difficultyKey = difficulty.toLowerCase();
  const locations = locationsByDifficulty[difficultyKey] || locationsByDifficulty.easy;

  if (locations.length === 0) {
    return null;
  }

  const randomIndex = Math.floor(Math.random() * locations.length);
  return locations[randomIndex];
}

// Get difficulty tier based on progress (number of beaten games)
function getDifficultyTier(beatenGamesCount) {
  if (beatenGamesCount < 3) {
    return 'Easy';
  } else if (beatenGamesCount < 7) {
    return 'Medium';
  } else {
    return 'Hard';
  }
}

// Export to global scope
window.LOCATIONS_DATA = LOCATIONS_DATA;
window.locationsByDifficulty = locationsByDifficulty;
window.getRandomLocation = getRandomLocation;
window.getDifficultyTier = getDifficultyTier;
