import json
from pathlib import Path

# Path to your JSON file
json_file = Path("SportData.json")

# Load existing games
if json_file.exists():
    with open(json_file) as f:
        games = json.load(f)
else:
    games = []

# New game to add or update
new_game = {
    "sport": 1,
    "home": False,
    "team": "JV Girls",
    "opponent": "Charter",
    "time": "5:00",
    "date": "Oct 9",
    "completed": False,
    "setsWon": 2,
    "setsLost": 1,
    "scores": [
        {"set": 1, "teamScore": 25, "oppScore": 10},
        {"set": 2, "teamScore": 25, "oppScore": 27},
        {"set": 3, "teamScore": 25, "oppScore": 5}
    ]
}

# Check if the same game exists
for i, g in enumerate(games):
    if (
        g.get("opponent") == new_game["opponent"] and
        g.get("time") == new_game["time"] and
        g.get("setsWon") == new_game["setsWon"] and
        g.get("setsLost") == new_game["setsLost"]
    ):
        games[i] = new_game  # update existing
        break
else:
    games.append(new_game)    # add new if not found

# Save updated JSON
with open(json_file, "w") as f:
    json.dump(games, f, indent=2)
