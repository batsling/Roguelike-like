#!/usr/bin/env python3
"""One-shot: Super Auto Pets' hats, for the players to wear (docs/customization.md §7).

The owner, 14 Nov 2026: "put hats on the player character similarly to how it
works in super auto pets … make sure the hats are facing the right way, I think
you need to flip all of them horizontally. Any play to unlock or purchasable hats
from super auto pets are super auto pets level up rewards. Don't add special hats
except the abandon hat … Only use current images."

So, off the wiki's Hats page (superautopets.fandom.com/wiki/Hats):

  * every NORMAL ("Play to Unlock") and IAP (bought in the Hat store) hat, at its
    CURRENT picture — the `…New.png` / `… 2x.png` column, never "Previous
    Version" — fetched as the wiki's ORIGINAL file (imageinfo), not a thumbnail;
  * the ABANDON HAT, the one special hat, whose current picture is DunceHat.png.
    It goes in `Special/`, which the index reads as "not a rank reward".

Each picture is MIRRORED on the way in: the wiki draws every hat facing right
(a cap's brim, a cowboy hat's dip) and the players face the other way.

Names are the wiki's, with two of its typos mended ("Rude Hate" -> Rude Hat,
"Flat top Hat" -> Flat Top Hat). The wiki's play-to-unlock "Real Bucket Hat"
links the very file the bought Bucket Hat does, so it is one hat here.

  python3 tools/oneshots/_hats_super_auto_pets.py
"""

import io
import json
import os
import urllib.parse
import urllib.request

from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "images2.0", "hats")
API = "https://superautopets.fandom.com/api.php"
UA = {"User-Agent": "Mozilla/5.0 (Roguelike-like hat import)"}
GAME = "Super_Auto_Pets"

# (name, wiki file of the CURRENT picture)
NORMAL = [
	("Astronaut Helmet", "AstronautHelmet 2x.png"), ("Ball Cap", "BallCap 2x.png"),
	("Balmoral Bonnet", "BalmoralBonnet 2x.png"), ("Baseball Hat", "BaseballHatNew.png"),
	("Bear Hat", "BearHatNew.png"), ("Bearskin Hat", "Bearskin 2x.png"),
	("Beret Hat", "BeretHatNew.png"), ("Biretta Hat", "Biretta 2x.png"),
	("Boudoir Cap", "BoudoirCap 2x.png"), ("Bowler Hat", "BowlerHat 2x.png"),
	("Bullseye Hat", "BullseyeHat 2x.png"), ("Cangaceiro Hat", "CangaceitoHat 2x.png"),
	("Captain Hat", "CaptainHatNew.png"), ("Carnival Tiara", "CarnivalTiara 2x.png"),
	("Chef Hat", "ChefHat 2x.png"), ("Cloche Hat", "ClocheHat 2x.png"),
	("Coonskin Hat", "CoonskinHat 2x.png"), ("Cowboy Hat", "CowboyHatNew.png"),
	("Custodian Helmet", "CustodianHelmet 2x.png"), ("Elf Hat", "ElfHatNew.png"),
	("Feather Hat", "PinocchioHat 2x.png"), ("Fedora Hat", "FedoraHatNew.png"),
	("Fez Hat", "FezHatNew.png"), ("Fish Hat", "FishCap 2x.png"),
	("Fishing Hat", "FishingHat 2x.png"), ("Flat Top Hat", "Boater 2x.png"),
	("Flower Hat", "FlowerHatNew.png"), ("Gaucho Hat", "GauchoHat 2x.png"),
	("Golden Poop Hat", "GoldenPoopHatNew.png"), ("Graduation Cap", "Mortarboard 2x.png"),
	("Hennin Hat", "Hennin 2x.png"), ("Inventor Hat", "InventorHatNew.png"),
	("June Party Hat", "JunePartyHat 2x.png"), ("Kepi Hat", "KepiHatNew.png"),
	("Kufi Hat", "Kufi 2x.png"), ("Moon Hat", "MoonHat 2x.png"),
	("Napoleon Hat", "Bicorne 2x.png"), ("Nefertiti Hat", "NefertitiHat 2x.png"),
	("Nurse Hat", "NurseHatNew.png"), ("Old Top Hat", "OldTopHatNew.png"),
	("Pamela Hat", "PamelaHatNew.png"), ("Pants Hat", "PantsHat 2x.png"),
	("Park Ranger Hat", "ParkRangerHat 2x.png"), ("Party Hat", "PartyHatNew.png"),
	("Pilgrim Hat", "PilgrimHatNew.png"), ("Pirate Hat", "PirateHatNew.png"),
	("Poop Hat", "PoopHatNew.png"), ("Propeller Hat", "PropelierHat 2x.png"),
	("Rasta Hat", "Rastacap 2x.png"), ("Robot Mask", "RobotHat_2x.png"),
	("Rude Hat", "ScumbagSteveHat 2x.png"), ("Samo", "Samo 2x.png"),
	("Santa Hat", "SantaHatNew.png"), ("Sherlock Hat", "SherlockHolmesHat 2x.png"),
	("Shower Head Cap", "ShowerHeadHat 2x.png"), ("Soda Cap", "SodaCap 2x.png"),
	("Soft Ice Hat", "IceCreamCone 2x.png"), ("Sombrero Hat", "Sombrero 2x.png"),
	("Straw Hat", "ConicalAsianHat 2x.png"), ("Sun Hat", "SunHat 2x.png"),
	("Tengu Mask", "TenguMask 2x.png"), ("Top Hat", "TopHatNew.png"),
	("Turban", "Turban 2x.png"), ("Umbrella Hat", "UmbrellaHat 2x.png"),
	("Uncle Sam Hat", "UncleSamHatNew.png"), ("Viking Hat", "VikingHelmet 2x.png"),
	("White Wig", "WhiteWig 2x.png"), ("Winter Hat", "WinterHatNew.png"),
	("Witch Hat", "WitchHat 2x.png"), ("Wizard Hat", "WizardHat 2x.png"),
]
BOUGHT = [
	("Beehive Hat", "Beehive_Hat.png"), ("Bird Nest", "Bird_Nest.png"),
	("Bucket Hat", "Bucket_Hat.png"), ("Cooking Pot", "Cooking_Pot.png"),
	("Early Adopter Hat", "EarlyAdopterHat.png"), ("Folded Newspaper", "Folded_Newspaper.png"),
	("Fruit Hat", "Fruit_Hat.png"), ("Halo", "Halo.png"), ("Hamburger Hat", "Hamburger_Hat.png"),
	("Mushroom Hat", "Mushroom_Hat.png"), ("Plant Hat", "Plant_Hat.png"), ("Plunger", "Plunger.png"),
	("Rainbow Hat", "Rainbow_Hat.png"), ("Stack of Hats", "Stack_of_Hats.png"),
	("Sunny Egg Hat", "Sunny_Egg_Hat.png"), ("Taco Hat", "Taco_Hat.png"),
	("Tin Foil Hat", "Tin_Foil_Hat.png"), ("Traffic Cone", "Traffic_Cone.png"),
]
SPECIAL = [("Abandon Hat", "DunceHat.png")]


def get(url: str) -> bytes:
	with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
		return r.read()


def originals(files: list) -> dict:
	"""wiki file name -> URL of its original upload."""
	out = {}
	for i in range(0, len(files), 40):
		chunk = files[i:i + 40]
		q = urllib.parse.urlencode({"action": "query", "format": "json", "prop": "imageinfo",
			"iiprop": "url", "titles": "|".join("File:" + f for f in chunk)})
		d = json.loads(get(API + "?" + q))
		back = {n["to"]: n["from"] for n in d["query"].get("normalized", [])}
		for p in d["query"]["pages"].values():
			info = p.get("imageinfo")
			if info:
				title = back.get(p["title"], p["title"])
				out[title[len("File:"):]] = info[0]["url"]
				# The canonical title too, so "Bucket Hat.png" and "Bucket_Hat.png" agree.
				out[p["title"][len("File:"):]] = info[0]["url"]
	return out


def main():
	rows = [(n, f, "") for n, f in NORMAL + BOUGHT] + [(n, f, "Special") for n, f in SPECIAL]
	urls = originals([f for _, f, _ in rows])
	for name, f, sub in rows:
		url = urls.get(f) or urls.get(f.replace("_", " "))
		if url is None:
			raise SystemExit(f"{name}: no file {f!r} on the wiki")
		img = Image.open(io.BytesIO(get(url))).convert("RGBA")
		img = ImageOps.mirror(img)
		box = img.getbbox()
		if box:
			img = img.crop(box)
		folder = os.path.join(OUT, sub) if sub else OUT
		os.makedirs(folder, exist_ok=True)
		stem = "%s_%s" % (name.replace(" ", "_"), GAME)
		img.save(os.path.join(folder, stem + ".png"), optimize=True)
		print(f"{sub + '/' if sub else ''}{stem}.png  {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
	main()
