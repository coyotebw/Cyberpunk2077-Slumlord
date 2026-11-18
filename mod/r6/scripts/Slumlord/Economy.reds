// Tuning and pure economy math. No game-state access here.
// ALL NUMBERS ARE PLACEHOLDERS until the pricing pass. Change them in SlumlordTuning only.
module Slumlord

public abstract class SlumlordTuning {

  // Purchase price per unit, by district wealth tier.
  public static func PricePerUnit(wealthTier: Int32) -> Int32 {
    switch wealthTier {
      case 1: return 1500;
      case 2: return 2500;
      case 3: return 4000;
      case 4: return 6500;
      case 5: return 10000;
      default: return 2500;
    }
  }

  // Weekly rent per occupied unit at rank D, by district wealth tier.
  public static func RentPerUnit(wealthTier: Int32) -> Int32 {
    switch wealthTier {
      case 1: return 60;
      case 2: return 100;
      case 3: return 160;
      case 4: return 260;
      case 5: return 400;
      default: return 100;
    }
  }

  // Rent multiplier by rank index: 0 = D, 1 = C, 2 = B, 3 = A, 4 = S.
  public static func RankMultiplier(rank: Int32) -> Float {
    switch rank {
      case 0: return 1.0;
      case 1: return 1.25;
      case 2: return 1.5;
      case 3: return 1.8;
      case 4: return 2.2;
      default: return 1.0;
    }
  }

  // ---- Tenants (design doc 4.3). Rank index: 0 = D ... 4 = S. Safety: 1..5, 3 = neutral.

  // New tenants per building per week at safety 3. S (negative) fills every empty unit each week.
  public static func ArrivalsPerWeek(rank: Int32) -> Float {
    switch rank {
      case 0: return 0.40;
      case 1: return 0.70;
      case 2: return 1.20;
      case 3: return 2.50;
      default: return -1.0;
    }
  }

  // Chance per residential tenant per week of moving out, at safety 3.
  public static func MoveOutChance(rank: Int32) -> Float {
    switch rank {
      case 0: return 0.06;
      case 1: return 0.045;
      case 2: return 0.03;
      case 3: return 0.02;
      default: return 0.01;
    }
  }

  // Chance per week that a commercial (business) tenant leaves. Rank only; safety does not apply.
  public static func CommercialMoveOutChance(rank: Int32) -> Float {
    switch rank {
      case 0: return 0.03;
      case 1: return 0.0225;
      case 2: return 0.015;
      case 3: return 0.01;
      default: return 0.005;
    }
  }

  public static func SafetyArrivalMultiplier(safety: Int32) -> Float {
    switch safety {
      case 1: return 0.70;
      case 2: return 0.85;
      case 4: return 1.15;
      case 5: return 1.30;
      default: return 1.0;
    }
  }

  public static func SafetyMoveOutMultiplier(safety: Int32) -> Float {
    switch safety {
      case 1: return 1.5;
      case 2: return 1.25;
      case 4: return 0.8;
      case 5: return 0.6;
      default: return 1.0;
    }
  }

  // ---- Contractors and rank bars (design doc 4.4). Stars 1..5; fit 0 poor .. 3 great.

  public static func ContractorFee(stars: Int32) -> Int32 {
    switch stars {
      case 1: return 500;
      case 2: return 1500;
      case 3: return 4000;
      case 4: return 10000;
      default: return 25000;
    }
  }

  public static func ContractorPoints(stars: Int32) -> Int32 {
    switch stars {
      case 1: return 600;
      case 2: return 2000;
      case 3: return 6000;
      case 4: return 16000;
      default: return 45000;
    }
  }

  public static func FitMultiplier(fit: Int32) -> Float {
    switch fit {
      case 3: return 1.5;
      case 2: return 1.0;
      case 1: return 0.6;
      default: return 0.3;
    }
  }

  // Points to rank up from `rank`, as a share of the purchase price (D->C, C->B, B->A, A->S).
  public static func RankBarShare(rank: Int32) -> Float {
    switch rank {
      case 0: return 0.30;
      case 1: return 0.50;
      case 2: return 0.80;
      default: return 1.20;
    }
  }

  public static func JobsPerRentDay() -> Int32 { return 3; }

  // Most weeks of tenant changes simulated in one catch-up (long sleeps, old saves).
  public static func MaxTenantCatchUpWeeks() -> Int32 { return 52; }

  public static func StartingOccupancyPercent() -> Int32 { return 60; }
  public static func StartingCondition() -> Int32 { return 70; }
  public static func MaxUncollectedWeeks() -> Int32 { return 4; }
  public static func DaysPerRentCycle() -> Int32 { return 7; }
  public static func TickIntervalSeconds() -> Float { return 30.0; }
  public static func MaxRank() -> Int32 { return 4; }
}

public abstract class SlumlordEconomy {

  public static func Price(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>) -> Int32 {
    if !IsDefined(def) || !IsDefined(district) { return 0; }
    if def.fixedPrice > 0 { return def.fixedPrice; }
    return def.units * SlumlordTuning.PricePerUnit(district.wealthTier);
  }

  public static func WeeklyRent(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>, state: ref<SlumlordPropertyState>) -> Int32 {
    if !IsDefined(def) || !IsDefined(district) || !IsDefined(state) || !state.owned { return 0; }
    let base = state.occupiedUnits * SlumlordEconomy.RentPerUnit(def, district);
    return RoundF(Cast<Float>(base) * SlumlordTuning.RankMultiplier(state.rank));
  }

  // What a listing should earn per week right after purchase (rank D, starting occupancy).
  public static func EstimatedWeeklyRent(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>) -> Int32 {
    if !IsDefined(def) || !IsDefined(district) { return 0; }
    return SlumlordEconomy.StartingOccupiedUnits(def) * SlumlordEconomy.RentPerUnit(def, district);
  }

  // Weekly rent per occupied unit at rank D: the property's own figure if it has one, else the district's.
  public static func RentPerUnit(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>) -> Int32 {
    if def.fixedRent > 0 { return def.fixedRent; }
    return SlumlordTuning.RentPerUnit(district.wealthTier);
  }

  public static func StartingOccupiedUnits(def: ref<SlumlordPropertyDef>) -> Int32 {
    if !IsDefined(def) { return 0; }
    if def.startingUnits > 0 { return Min(def.startingUnits, def.units); }
    return Max(1, (def.units * SlumlordTuning.StartingOccupancyPercent()) / 100);
  }

  public static func RankLetter(rank: Int32) -> String {
    switch rank {
      case 0: return "D";
      case 1: return "C";
      case 2: return "B";
      case 3: return "A";
      case 4: return "S";
      default: return "?";
    }
  }

  // Design system money format: "€$ 12,400". No decimals.
  public static func FormatMoney(amount: Int32) -> String {
    let negative = amount < 0;
    let digits = IntToString(negative ? -amount : amount);
    let len = StrLen(digits);
    let out = "";
    let i = 0;
    while i < len {
      if i > 0 && (len - i) % 3 == 0 {
        out = out + ",";
      }
      out = out + StrMid(digits, i, 1);
      i += 1;
    }
    return (negative ? "-" : "") + "€$ " + out;
  }
}
