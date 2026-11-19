// Static definitions: districts and properties.
// Names, unit counts and district numbers are DRAFTS. Edit freely; ids must stay stable once
// saves exist, because save data is keyed by property id.
module Slumlord

public class SlumlordDistrictDef {
  public let id: CName;
  public let displayName: String;
  public let katakana: String;          // vertical label on the district card
  public let wealthTier: Int32;         // 1 (poorest) .. 5 (richest): drives price and rent
  public let streetCredRequired: Int32; // district unlocks at this Street Cred
  public let safety: Int32;             // 1 (combat zone) .. 5 (corp-policed): drives tenant arrivals and move-outs
  public let rival: String;             // rival landlord display name; the portal shows "Unknown" until V has met them
  public let gangs: String;             // display only for now
}

public class SlumlordPropertyDef {
  public let id: CName;
  public let districtId: CName;
  public let displayName: String;
  public let units: Int32;
  public let commercial: Bool;    // shop or business space: one business tenant per unit
  public let fixedPrice: Int32;   // €$; 0 = district formula
  public let fixedRent: Int32;    // €$ per occupied unit per week at rank D; 0 = district formula
  public let startingUnits: Int32; // tenants on purchase; 0 = StartingOccupancyPercent of units (at least 1)
}

public abstract class SlumlordData {

  public static func Districts() -> array<ref<SlumlordDistrictDef>> {
    let list: array<ref<SlumlordDistrictDef>>;
    ArrayPush(list, SlumlordData.District(n"watson",        "Watson",        "ワトソン",         2,  0, "Hideyoshi Oshima",       "Tyger Claws, Maelstrom", 2));
    ArrayPush(list, SlumlordData.District(n"santo_domingo", "Santo Domingo", "サントドミンゴ",   1,  5, "Quentin Finger",         "6th Street", 2));
    ArrayPush(list, SlumlordData.District(n"pacifica",      "Pacifica",      "パシフィカ",       1, 10, "Ozob Bozo",              "Voodoo Boys, Animals", 1));
    ArrayPush(list, SlumlordData.District(n"badlands",      "Badlands",      "バッドランズ",     1, 10, "TBD",                    "Wraiths", 1));
    ArrayPush(list, SlumlordData.District(n"heywood",       "Heywood",       "ヘイウッド",       3, 15, "TBD",                    "Valentinos", 3));
    ArrayPush(list, SlumlordData.District(n"westbrook",     "Westbrook",     "ウエストブルック", 4, 25, "TBD",                    "Tyger Claws", 4));
    ArrayPush(list, SlumlordData.District(n"city_center",   "City Center",   "シティセンター",   5, 40, "TBD",                    "None (NCPD permit fees)", 5));
    return list;
  }

  public static func Properties() -> array<ref<SlumlordPropertyDef>> {
    let list: array<ref<SlumlordPropertyDef>>;

    // Watson: Little China, Kabuki, Northside, Arasaka Waterfront
    ArrayPush(list, SlumlordData.Commercial(n"wat_kabuki_court",   n"watson", "Kabuki Shop Booth", 10000, 850)); // id kept: save data is keyed by it
    ArrayPush(list, SlumlordData.Commercial(n"wat_capitan_caliente", n"watson", "Capitan Caliente, Ellison St", 6350, 650));
    ArrayPush(list, SlumlordData.Priced(n"wat_bradbury_boreas",    n"watson", "Bradbury & Boreas",         4, 9275, 160));
    ArrayPush(list, SlumlordData.Priced(n"wat_kabuki_waterfront",  n"watson", "Kabuki Waterfront",         3, 3499, 110));
    ArrayPush(list, SlumlordData.Priced(n"wat_harbor_safehouse",   n"watson", "Harbor Safehouse",          6, 5150, 109, 1));

    // Santo Domingo: Arroyo, Rancho Coronado
    ArrayPush(list, SlumlordData.Priced(n"sd_suburban_adu",        n"santo_domingo", "Charming Suburban ADU",     2, 1500, 60));
    ArrayPush(list, SlumlordData.Priced(n"sd_dam_bungalow",        n"santo_domingo", "Dam Bungalow",              4, 2500, 76, 2));
    ArrayPush(list, SlumlordData.Commercial(n"sd_chooh2_carnitas", n"santo_domingo", "Chooh2 Carnitas St", 6435, 500));
    ArrayPush(list, SlumlordData.Commercial(n"sd_manufactory_stall", n"santo_domingo", "Manufactory Food Stall", 4400, 350));
    ArrayPush(list, SlumlordData.Priced(n"sd_mission_garages",     n"santo_domingo", "Mission St Garages",        3, 3400, 85));

    // Pacifica: Coastview, West Wind Estate
    ArrayPush(list, SlumlordData.Property(n"pac_resort_ruins",     n"pacifica", "Coastview Resort Ruins",  30));
    ArrayPush(list, SlumlordData.Property(n"pac_westwind_blocks",  n"pacifica", "West Wind Estate Blocks", 24));
    ArrayPush(list, SlumlordData.Property(n"pac_pier_rooms",       n"pacifica", "Pacifica Pier Rooms",     10));
    ArrayPush(list, SlumlordData.Property(n"pac_hotel_annex",      n"pacifica", "Coastview Hotel Annex",   18));
    ArrayPush(list, SlumlordData.Property(n"pac_squat_towers",     n"pacifica", "West Wind Squat Towers",  28));

    // Badlands: Rocky Ridge, Red Peaks, Laguna Bend, Jackson Plains, Biotechnica Flats
    ArrayPush(list, SlumlordData.Property(n"bad_rockyridge_motel", n"badlands", "Rocky Ridge Motor Lodge",   12));
    ArrayPush(list, SlumlordData.Property(n"bad_redpeaks_trailers", n"badlands", "Red Peaks Trailer Park",   16));
    ArrayPush(list, SlumlordData.Property(n"bad_laguna_cabins",    n"badlands", "Laguna Bend Lake Cabins",    8));
    ArrayPush(list, SlumlordData.Property(n"bad_jackson_bunkhouse", n"badlands", "Jackson Plains Bunkhouse", 14));
    ArrayPush(list, SlumlordData.Property(n"bad_biotech_housing",  n"badlands", "Biotechnica Worker Housing", 20));

    // Heywood: The Glen, Wellsprings, Vista del Rey
    ArrayPush(list, SlumlordData.Property(n"hey_glen_plaza",       n"heywood", "Glen Plaza Apartments",    18));
    ArrayPush(list, SlumlordData.Property(n"hey_wellsprings_court", n"heywood", "Wellsprings Garden Court", 12));
    ArrayPush(list, SlumlordData.Property(n"hey_vista_tenement",   n"heywood", "Vista del Rey Tenement",   22));
    ArrayPush(list, SlumlordData.Property(n"hey_palms_lodge",      n"heywood", "Palms Motor Lodge",        10));
    ArrayPush(list, SlumlordData.Property(n"hey_glen_walkup",      n"heywood", "Glen Market Walk-Up",      14));

    // Westbrook: Japantown, Charter Hill, North Oak
    ArrayPush(list, SlumlordData.Property(n"wb_jtown_lofts",       n"westbrook", "Japantown Neon Lofts",     14));
    ArrayPush(list, SlumlordData.Property(n"wb_sakura_suites",     n"westbrook", "Sakura Row Suites",        10));
    ArrayPush(list, SlumlordData.Property(n"wb_capsule_hotel",     n"westbrook", "Japantown Capsule Hotel",  40));
    ArrayPush(list, SlumlordData.Property(n"wb_charter_terraces",  n"westbrook", "Charter Hill Terraces",     8));
    ArrayPush(list, SlumlordData.Property(n"wb_northoak_annex",    n"westbrook", "North Oak Villa Annex",     4));

    // City Center: Corpo Plaza, Downtown
    ArrayPush(list, SlumlordData.Property(n"cc_plaza_microsuites", n"city_center", "Corpo Plaza Micro-Suites",  30));
    ArrayPush(list, SlumlordData.Property(n"cc_downtown_flats",    n"city_center", "Downtown Tower Flats",      20));
    ArrayPush(list, SlumlordData.Property(n"cc_skyline_rentals",   n"city_center", "Skyline Executive Rentals",  6));
    ArrayPush(list, SlumlordData.Property(n"cc_parking_stack",     n"city_center", "Parking Stack Apartments",  16));
    ArrayPush(list, SlumlordData.Property(n"cc_plaza_heights",     n"city_center", "Plaza Heights",             12));

    return list;
  }

  private static func District(id: CName, name: String, kana: String, wealth: Int32, cred: Int32, rival: String, gangs: String, safety: Int32) -> ref<SlumlordDistrictDef> {
    let d = new SlumlordDistrictDef();
    d.id = id;
    d.displayName = name;
    d.katakana = kana;
    d.wealthTier = wealth;
    d.streetCredRequired = cred;
    d.rival = rival;
    d.gangs = gangs;
    d.safety = Clamp(safety, 1, 5);
    return d;
  }

  // A single shop or business space with its own price and weekly rent.
  private static func Commercial(id: CName, district: CName, name: String, price: Int32, weeklyRent: Int32) -> ref<SlumlordPropertyDef> {
    let p = SlumlordData.Property(id, district, name, 1);
    p.commercial = true;
    p.fixedPrice = price;
    p.fixedRent = weeklyRent;
    return p;
  }

  // Residential with a set purchase price and a set weekly rent per occupied unit (tenant).
  // startTenants: tenants on purchase; leave out for the default (60% of units, at least 1).
  private static func Priced(id: CName, district: CName, name: String, units: Int32, price: Int32, rentPerUnit: Int32, opt startTenants: Int32) -> ref<SlumlordPropertyDef> {
    let p = SlumlordData.Property(id, district, name, units);
    p.fixedPrice = price;
    p.fixedRent = rentPerUnit;
    p.startingUnits = startTenants;
    return p;
  }

  private static func Property(id: CName, district: CName, name: String, units: Int32) -> ref<SlumlordPropertyDef> {
    let p = new SlumlordPropertyDef();
    p.id = id;
    p.districtId = district;
    p.displayName = name;
    p.units = units;
    return p;
  }
}
