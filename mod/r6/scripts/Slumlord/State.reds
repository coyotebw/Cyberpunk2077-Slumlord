// Per-property save state. Every field must be `persistent` or it resets on load.
// String cannot be persisted, so ids are CName.
module Slumlord

public class SlumlordPropertyState {
  public persistent let id: CName;
  public persistent let owned: Bool;
  public persistent let rank: Int32;             // 0 = D ... 4 = S
  public persistent let occupiedUnits: Int32;
  public persistent let condition: Int32;        // 0..100
  public persistent let uncollected: Int32;      // €$ waiting at the portal
  public persistent let weeksUncollected: Int32; // capped by SlumlordTuning.MaxUncollectedWeeks()
  public persistent let reportIn: Int32;         // tenants moved in since the last tenant report (Tenants.reds)
  public persistent let reportOut: Int32;        // tenants moved out since the last tenant report
}

public enum SlumlordBuyResult {
  Ok = 0,
  UnknownProperty = 1,
  AlreadyOwned = 2,
  DistrictLocked = 3,
  NotEnoughMoney = 4,
  NoPlayer = 5
}
