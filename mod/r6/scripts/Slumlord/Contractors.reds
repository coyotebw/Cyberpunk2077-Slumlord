// Contractors: hired from the portal to renovate a property and raise its rank (design doc 4.4).
// Yakuza 0's advisors, Night City edition. Each job costs the Contractor's fee and adds points to the
// property's rank bar; a full bar raises the rank by one at once. Points past the next rank are lost.
// At most SlumlordTuning.JobsPerRentDay() jobs per property per rent day.
// Points per job = tier points x fit for the property's type (residential or commercial).
// Two Contractors per district, available once the district is unlocked (Street Cred); two more come
// from quests or fixers (unlock TBD: SlumlordSystem.UnlockContractor).
module Slumlord

public class SlumlordContractorDef {
  public let id: CName;
  public let crew: String;
  public let boss: String;
  public let districtId: CName;      // available with this district; n"" = quest/fixer unlock
  public let stars: Int32;           // 1..5: fee and points per job (SlumlordTuning)
  public let fitResidential: Int32;  // 0 poor (×), 1 fair (△), 2 good (○), 3 great (◎)
  public let fitCommercial: Int32;
  public let pitch: String;
}

public abstract class SlumlordContractors {

  public static func All() -> array<ref<SlumlordContractorDef>> {
    let list: array<ref<SlumlordContractorDef>>;
    // Watson (Street Cred 0): the starting pair.
    ArrayPush(list, SlumlordContractors.C(n"con_dumpster_dan",   "Dumpster Dan's Handyman Service", "Dan Kowalczyk",    n"watson",        1, 2, 1, "Works out of a van, takes cash, asks nothing."));
    ArrayPush(list, SlumlordContractors.C(n"con_lin_daughters",  "Lin & Daughters Shopfitting",     "Mei Lin",          n"watson",        2, 1, 3, "Three generations of Kabuki market stalls."));
    // Santo Domingo (5)
    ArrayPush(list, SlumlordContractors.C(n"con_arroyo_steel",   "Arroyo Steelworks",               "Héctor Ruiz",      n"santo_domingo", 2, 2, 2, "Laid-off plant welders. Solid all-rounders."));
    ArrayPush(list, SlumlordContractors.C(n"con_coronado_dry",   "Coronado Drywall Co.",            "Tasha Greene",     n"santo_domingo", 2, 3, 0, "Suburban flipper. Great at apartments, useless with shops."));
    // Pacifica (10)
    ArrayPush(list, SlumlordContractors.C(n"con_coastview",      "Coastview Salvage",               "Zeke Baptiste",    n"pacifica",      2, 2, 1, "Strips the dead resort towers for parts."));
    ArrayPush(list, SlumlordContractors.C(n"con_grand_imperial", "Grand Imperial Interiors",        "Marisol Duvall",   n"pacifica",      3, 1, 3, "Fitted out the mall before the money left."));
    // Badlands (10)
    ArrayPush(list, SlumlordContractors.C(n"con_sunset_motel",   "Sunset Motel Maintenance",        "Gus Pruitt",       n"badlands",      2, 2, 2, "Has kept the motel strip standing for 30 years."));
    ArrayPush(list, SlumlordContractors.C(n"con_dust_devil",     "Dust Devil Builders",             "Kestrel Vance",    n"badlands",      3, 3, 1, "Nomad crew. Builds anything out of anything."));
    // Heywood (15)
    ArrayPush(list, SlumlordContractors.C(n"con_wellsprings",    "Wellsprings Restoration",         "Rosa Ibáñez",      n"heywood",       3, 3, 2, "Period façades, real tile, slow talker."));
    ArrayPush(list, SlumlordContractors.C(n"con_glen_shopfront", "Glen Shopfronts",                 "Darnell Okafor",   n"heywood",       3, 1, 3, "Neon, shutters, storefronts that sell."));
    // Westbrook (25)
    ArrayPush(list, SlumlordContractors.C(n"con_kitagawa",       "Kitagawa Design Build",           "Haruka Kitagawa",  n"westbrook",     4, 2, 3, "Japantown boutiques and clubs."));
    ArrayPush(list, SlumlordContractors.C(n"con_charter_hill",   "Charter Hill Living",             "Oliver Prentice",  n"westbrook",     4, 3, 1, "Luxury condo fit-outs for corpo money."));
    // City Center (40)
    ArrayPush(list, SlumlordContractors.C(n"con_halvorsen",      "Halvorsen Smart Living",          "Ingrid Halvorsen", n"city_center",   4, 3, 2, "Smart-home everything, subscription included."));
    ArrayPush(list, SlumlordContractors.C(n"con_meridian",       "Meridian Tower Group",            "Julian Achebe",    n"city_center",   5, 2, 3, "Corp-grade. Builds lobbies that intimidate."));
    // Quest / fixer unlocks (TBD).
    ArrayPush(list, SlumlordContractors.C(n"con_architect",      "\"The Architect\"",               "Name unknown",     n"",              5, 3, 3, "Rumoured ex-Arasaka designer. One gig at a time."));
    ArrayPush(list, SlumlordContractors.C(n"con_oshima",         "Oshima Location Services",        "Hideyoshi Oshima", n"",              4, 3, 2, "Dresses your property as a braindance set. Insists on filming."));
    return list;
  }

  private static func C(id: CName, crew: String, boss: String, district: CName, stars: Int32, fitRes: Int32, fitCom: Int32, pitch: String) -> ref<SlumlordContractorDef> {
    let c = new SlumlordContractorDef();
    c.id = id;
    c.crew = crew;
    c.boss = boss;
    c.districtId = district;
    c.stars = Clamp(stars, 1, 5);
    c.fitResidential = Clamp(fitRes, 0, 3);
    c.fitCommercial = Clamp(fitCom, 0, 3);
    c.pitch = pitch;
    return c;
  }

  public static func Fit(c: ref<SlumlordContractorDef>, property: ref<SlumlordPropertyDef>) -> Int32 {
    return property.commercial ? c.fitCommercial : c.fitResidential;
  }

  public static func FitWord(fit: Int32) -> String {
    switch fit {
      case 3: return "Great";
      case 2: return "Good";
      case 1: return "Fair";
      default: return "Poor";
    }
  }

  // Yakuza's symbols. Shown only while SlumlordUi.GlyphsEnabled() (not yet checked in the game font).
  public static func FitGlyph(fit: Int32) -> String {
    switch fit {
      case 3: return "◎";
      case 2: return "○";
      case 1: return "△";
      default: return "×";
    }
  }

  // Points one job adds to this property's rank bar.
  public static func JobPoints(c: ref<SlumlordContractorDef>, property: ref<SlumlordPropertyDef>) -> Int32 {
    let base = Cast<Float>(SlumlordTuning.ContractorPoints(c.stars));
    return RoundF(base * SlumlordTuning.FitMultiplier(SlumlordContractors.Fit(c, property)));
  }
}

public enum SlumlordHireResult {
  Progress = 0,          // points added, same rank
  RankedUp = 1,          // bar filled: rank +1
  UnknownProperty = 2,
  NotOwned = 3,
  MaxRank = 4,
  JobLimit = 5,
  ContractorLocked = 6,
  NotEnoughMoney = 7,
  NoPlayer = 8
}
