-- Verified NPC -> display ID references (OctoWoW DB).
-- Small Crag Boar (708) sourced from alpha DB (cross-check in Octo client).
-- Young Thistle Boar (1984) sourced from Capy DB (cross-check in Octo client).
-- Other 46 entries verified on OctoWoW DB.
BoarTrackerDisplayIDs = {
  [113] = 503, -- Stonetusk Boar
  [119] = 381, -- Longsnout
  [157] = 3027, -- Goretusk
  [330] = 8871, -- Princess
  [345] = 703, -- Bellygrub
  [390] = 377, -- Porcine Entourage
  [454] = 8871, -- Young Goretusk
  [524] = 389, -- Rockhide Boar
  [547] = 3035, -- Great Goretusk
  [708] = 607, -- Small Crag Boar
  [1125] = 607, -- Crag Boar
  [1126] = 381, -- Large Crag Boar
  [1127] = 744, -- Elder Crag Boar
  [1190] = 704, -- Mountain Boar
  [1191] = 3027, -- Mangy Mountain Boar
  [1192] = 1208, -- Elder Mountain Boar
  [1689] = 193, -- Scarred Crag Boar
  [1984] = 8869, -- Young Thistle Boar
  [1985] = 6807, -- Thistle Boar
  [2954] = 6807, -- Bristleback Battleboar
  [2966] = 8869, -- Battleboar
  [3098] = 503, -- Mottled Boar
  [3099] = 381, -- Dire Mottled Boar
  [3100] = 193, -- Elder Mottled Boar
  [3225] = 744, -- Corrupted Mottled Boar
  [4511] = 4713, -- Agam'ar
  [4512] = 4714, -- Rotting Agam'ar
  [4514] = 2453, -- Raging Agam'ar
  [5992] = 3026, -- Ashmane Boar
  [5993] = 11410, -- Helboar
  [7333] = 6121, -- Withered Battle Boar
  [8303] = 8870, -- Grunter
  [16117] = 6121, -- Plagued Swine
  [60848] = 3027, -- Bristleback Boar
  [60980] = 3027, -- Bramblethorn Boar
  [61689] = 20504, -- Young Thalassian Boar
  [61692] = 20504, -- Thalassian Boar
  [61696] = 20504, -- Elder Thalassian Boar
  [61975] = 20504, -- Hightusk Boar
  [62121] = 20504, -- Goldbristle Boar
  [62122] = 20504, -- Burly Goldbristle Boar
  [62226] = 389, -- Stonehide Boar
  [62227] = 389, -- Elder Stonehide Boar
  [62260] = 389, -- Forest Boar
  [62261] = 389, -- Elder Forest Boar
  [62262] = 6807, -- Mesa Boar
  [62271] = 20504, -- Young Goldbristle Boar
  [91987] = 503, -- Cragtusk Boar
}

-- NPCs sharing a display ID share one portrait texture. Two portraits were
-- cropped directly from in-game unit frames; the other 21 are head-biased crops
-- from the same full-model Classic webthumb images referenced by Tortoise DB
-- Viewer. Those approximations are not exact 1.12 unit-frame camera renders.
BoarTrackerPortraitTextures = {
  [389] = "BoarPortrait", -- Existing in-game Stonehide portrait
  [20504] = "GoldbristlePortrait", -- Existing in-game Goldbristle portrait
  [193] = "Portrait_193",
  [377] = "Portrait_377",
  [381] = "Portrait_381",
  [503] = "Portrait_503",
  [607] = "Portrait_607",
  [703] = "Portrait_703",
  [704] = "Portrait_704",
  [744] = "Portrait_744",
  [1208] = "Portrait_1208",
  [2453] = "Portrait_2453",
  [3026] = "Portrait_3026",
  [3027] = "Portrait_3027",
  [3035] = "Portrait_3035",
  [4713] = "Portrait_4713",
  [4714] = "Portrait_4714",
  [6121] = "Portrait_6121",
  [6807] = "Portrait_6807",
  [8869] = "Portrait_8869",
  [8870] = "Portrait_8870",
  [8871] = "Portrait_8871",
  [11410] = "Portrait_11410",
}
