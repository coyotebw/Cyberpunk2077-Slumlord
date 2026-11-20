// Slumlord core system: owns save state, weekly rent, buying and collecting.
// Game API calls were checked against working public mods (2026-11-16); still uncompiled.
module Slumlord

public class SlumlordSystem extends ScriptableSystem {

  // ---- Save data (written into each save file) ----
  private persistent let m_states: array<ref<SlumlordPropertyState>>;
  private persistent let m_lastRentWeek: Int32;
  private persistent let m_initialized: Bool;
  private persistent let m_lifetimeCollected: Int32;
  private persistent let m_empireComplete: Bool;
  private persistent let m_reportWeeks: Int32;   // rent days covered by the latest tenant report
  private persistent let m_rentDays: Int32;      // rent days processed on this save: seeds tenant rolls
  private persistent let m_unlockedContractors: array<CName>; // quest/fixer Contractors unlocked on this save
  // Latest alert text (Slumlord Realty's alert message, drawn by Tenants.reds). Strings can't be saved:
  // kind 1 = lease broken (Finger.reds); property id, name index (Names.reds), complaint index.
  private persistent let m_alertKind: Int32;
  private persistent let m_alertProperty: CName;
  private persistent let m_alertName: Int32;
  private persistent let m_alertComplaint: Int32;

  // ---- Runtime only ----
  private let m_districts: array<ref<SlumlordDistrictDef>>;
  private let m_properties: array<ref<SlumlordPropertyDef>>;
  private let m_contractors: array<ref<SlumlordContractorDef>>;
  private let m_tickId: DelayID;
  private let m_tickActive: Bool;
  private let m_pinIds: array<NewMappinID>;

  // ===================================================================== lifecycle

  public static func GetInstance(game: GameInstance) -> ref<SlumlordSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordSystem") as SlumlordSystem;
  }

  private func OnAttach() -> Void {
    this.EnsureLoaded();
  }

  private func OnRestored(saveVersion: Int32, gameVersion: Int32) -> Void {
    this.EnsureLoaded();
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.EnsureLoaded();
    if !this.m_initialized {
      // First run on this save: start the rent clock now, no back pay.
      this.m_lastRentWeek = this.CurrentWeek();
      this.m_initialized = true;
      ModLog(n"Slumlord", "Initialized on this save.");
    }
    this.Refresh();
    this.RefreshPins();
    this.ScheduleTick();
  }

  private func OnDetach() -> Void {
    this.CancelTick();
  }

  // Definitions are code-defined; save state is matched to them by id.
  // New properties added in later versions get a fresh state entry.
  private func EnsureLoaded() -> Void {
    if ArraySize(this.m_districts) == 0 {
      this.m_districts = SlumlordData.Districts();
    }
    if ArraySize(this.m_properties) == 0 {
      this.m_properties = SlumlordData.Properties();
    }
    if ArraySize(this.m_contractors) == 0 {
      this.m_contractors = SlumlordContractors.All();
    }
    // Renamed ids: move saved state over to the current id.
    for s in this.m_states {
      let current = SlumlordData.CurrentId(s.id);
      if NotEquals(current, s.id) && !IsDefined(this.GetState(current)) {
        ModLog(n"Slumlord", "Renamed saved property " + NameToString(s.id) + " -> " + NameToString(current));
        s.id = current;
      }
    }
    this.m_alertProperty = SlumlordData.CurrentId(this.m_alertProperty);
    for def in this.m_properties {
      let existing = this.GetState(def.id);
      if IsDefined(existing) && existing.occupiedUnits > def.units {
        existing.occupiedUnits = def.units; // property resized since this save was made
      }
      if !IsDefined(existing) {
        let state = new SlumlordPropertyState();
        state.id = def.id;
        state.owned = false;
        state.rank = 0;
        state.occupiedUnits = 0;
        state.condition = SlumlordTuning.StartingCondition();
        state.uncollected = 0;
        state.weeksUncollected = 0;
        ArrayPush(this.m_states, state);
      }
    }
    // Drop saved properties whose id no longer exists (renamed or removed), so they don't count as owned.
    let i = ArraySize(this.m_states) - 1;
    while i >= 0 {
      if !IsDefined(this.GetPropertyDef(this.m_states[i].id)) {
        ModLog(n"Slumlord", "Dropped saved state for unknown property " + NameToString(this.m_states[i].id));
        ArrayErase(this.m_states, i);
      }
      i -= 1;
    }
  }

  // ===================================================================== time

  private func CurrentDay() -> Int32 {
    let timeSystem = GameInstance.GetTimeSystem(this.GetGameInstance());
    return GameTime.Days(timeSystem.GetGameTime());
  }

  private func CurrentWeek() -> Int32 {
    return this.CurrentDay() / SlumlordTuning.DaysPerRentCycle();
  }

  public func DaysUntilRentDay() -> Int32 {
    let cycle = SlumlordTuning.DaysPerRentCycle();
    return cycle - (this.CurrentDay() % cycle);
  }

  // Lazy accrual: works across sleeping, waiting and fast travel.
  // Each elapsed rent day, per owned property: rent for the week just ended (current occupancy),
  // then tenant move-outs and arrivals (Tenants.reds). One tenant report text covers them all.
  // Returns the number of rent days processed.
  public func Refresh() -> Int32 {
    this.EnsureLoaded();
    if !this.m_initialized { return 0; }
    let week = this.CurrentWeek();
    let elapsed = week - this.m_lastRentWeek;
    if elapsed <= 0 { return 0; }
    this.m_lastRentWeek = week;

    for state in this.m_states {
      state.reportIn = 0;
      state.reportOut = 0;
      state.jobsThisWeek = 0;   // Contractor job limit resets on rent day
    }
    let simWeeks = Min(elapsed, SlumlordTuning.MaxTenantCatchUpWeeks());
    let accrued = 0;
    let n = 0;
    while n < simWeeks {
      this.m_rentDays += 1;   // saved, so reloading replays the same rolls; forced debug rent days get new ones
      accrued += this.ProcessRentDay(this.m_rentDays);
      n += 1;
    }
    this.m_reportWeeks = simWeeks;
    let finger = SlumlordFinger.GetInstance(this.GetGameInstance());
    if IsDefined(finger) {
      finger.OnRentDay(this.m_rentDays);   // lease-broken events for the coming week
    }

    if this.GetOwnedCount() > 0 {
      this.RefreshPins();   // owned pins turn into rent-ready pins
      SlumlordTenantReport.Send(this.GetGameInstance());
    }
    if accrued > 0 {
      this.ShowMessage("Rent is due. " + SlumlordEconomy.FormatMoney(this.GetUncollectedTotal()) + " waiting to be collected.");
    }
    return elapsed;
  }

  // One rent day for every owned property. `rentDay` numbers it (seeds the tenant rolls). Returns the rent added.
  private func ProcessRentDay(rentDay: Int32) -> Int32 {
    let total = 0;
    for state in this.m_states {
      if state.owned {
        let def = this.GetPropertyDef(state.id);
        let district: ref<SlumlordDistrictDef>;
        if IsDefined(def) {
          district = this.GetDistrictDef(def.districtId);
        }
        if IsDefined(def) && IsDefined(district) {
          if state.weeksUncollected < SlumlordTuning.MaxUncollectedWeeks() {
            let amount = SlumlordEconomy.WeeklyRent(def, district, state);
            state.uncollected += amount;
            state.weeksUncollected += 1;
            total += amount;
          }
          SlumlordTenants.StepWeek(def, district, state, rentDay);
        }
      }
    }
    return total;
  }

  // Text of the latest tenant report (shown in Slumlord Realty's message).
  public func BuildTenantReport() -> String {
    this.EnsureLoaded();
    let weeks = this.m_reportWeeks;
    let title = weeks > 1 ? "Tenant report, last " + IntToString(weeks) + " weeks" : "Tenant report";
    let lines = "";
    let totalIn = 0;
    let totalOut = 0;
    let occupied = 0;
    let units = 0;
    for def in this.m_properties {
      let state = this.GetState(def.id);
      if IsDefined(state) && state.owned {
        occupied += state.occupiedUnits;
        units += def.units;
        totalIn += state.reportIn;
        totalOut += state.reportOut;
        if state.reportIn > 0 || state.reportOut > 0 {
          lines = lines + "\n" + SlumlordTenantReportLine.For(def, state.reportIn, state.reportOut);
        }
      }
    }
    let period = weeks > 1 ? "these weeks" : "this week";
    let summary = totalIn + totalOut == 0
      ? "Nobody moved in or out " + period + "."
      : "Moved in: " + IntToString(totalIn) + "   Moved out: " + IntToString(totalOut);
    return title + "\n" + summary + lines + "\nOccupied: " + IntToString(occupied) + " of " + IntToString(units) + " units";
  }

  // ===================================================================== tick

  private func ScheduleTick() -> Void {
    if this.m_tickActive { return; }
    let callback = new SlumlordTickCallback();
    callback.system = this;
    this.m_tickId = GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(callback, SlumlordTuning.TickIntervalSeconds(), false);
    this.m_tickActive = true;
  }

  private func CancelTick() -> Void {
    if this.m_tickActive {
      GameInstance.GetDelaySystem(this.GetGameInstance()).CancelCallback(this.m_tickId);
      this.m_tickActive = false;
    }
  }

  public func OnTick() -> Void {
    this.m_tickActive = false;
    this.Refresh();
    let finger = SlumlordFinger.GetInstance(this.GetGameInstance());
    if IsDefined(finger) {
      finger.OnSystemTick();
    }
    this.ScheduleTick();
  }

  // ===================================================================== player

  private func GetPlayer() -> ref<PlayerPuppet> {
    return GameInstance.GetPlayerSystem(this.GetGameInstance()).GetLocalPlayerMainGameObject() as PlayerPuppet;
  }

  public func GetPlayerMoney() -> Int32 {
    let player = this.GetPlayer();
    if !IsDefined(player) { return 0; }
    return GameInstance.GetTransactionSystem(this.GetGameInstance()).GetItemQuantity(player, MarketSystem.Money());
  }

  // What V can spend here: the wallet, plus Marmur checking when Marmur Bank is linked and would cover it (Bank.reds).
  public func GetSpendingPower() -> Int32 {
    return SlumlordBank.SpendingPower(this.GetGameInstance(), this.GetPlayerMoney());
  }

  // A payment out of V's wallet, topped up from Marmur checking if needed, posted to Marmur's ledger by name.
  private func Spend(amount: Int32, label: String, detail: String) -> Bool {
    let game = this.GetGameInstance();
    let auth = SlumlordBank.Authorize(game, amount, this.GetPlayerMoney());
    if this.GetPlayerMoney() < amount {
      SlumlordBank.Settle(game, auth, false);
      return false;
    }
    let entry = SlumlordBank.Begin(game);
    let ok = this.TakeMoney(amount);
    SlumlordBank.End(game, entry, label, detail);
    SlumlordBank.Settle(game, auth, ok);
    return ok;
  }

  // Money into V's wallet, posted to Marmur's ledger by name.
  private func Earn(amount: Int32, label: String, detail: String) -> Void {
    let game = this.GetGameInstance();
    let entry = SlumlordBank.Begin(game);
    this.GiveMoney(amount);
    SlumlordBank.End(game, entry, label, detail);
  }

  private func GiveMoney(amount: Int32) -> Void {
    let player = this.GetPlayer();
    if IsDefined(player) && amount > 0 {
      GameInstance.GetTransactionSystem(this.GetGameInstance()).GiveItem(player, MarketSystem.Money(), amount);
    }
  }

  private func TakeMoney(amount: Int32) -> Bool {
    let player = this.GetPlayer();
    if !IsDefined(player) { return false; }
    return GameInstance.GetTransactionSystem(this.GetGameInstance()).RemoveItem(player, MarketSystem.Money(), amount);
  }

  public func GetStreetCred() -> Int32 {
    let player = this.GetPlayer();
    if !IsDefined(player) { return 0; }
    let stats = GameInstance.GetStatsSystem(this.GetGameInstance());
    return RoundF(stats.GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.StreetCred));
  }

  // Standard on-screen warning message (same pattern as Let There Be Flight, Revised Backpack).
  private func ShowMessage(text: String) -> Void {
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 5.0;
    msg.message = text;
    let defs = GetAllBlackboardDefs();
    let board = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(defs.UI_Notifications);
    board.SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(msg), true);
  }

  // ===================================================================== lookups (also used by the portal UI)

  public func GetDistricts() -> array<ref<SlumlordDistrictDef>> {
    this.EnsureLoaded();
    return this.m_districts;
  }

  public func GetProperties() -> array<ref<SlumlordPropertyDef>> {
    this.EnsureLoaded();
    return this.m_properties;
  }

  public func GetDistrictDef(id: CName) -> ref<SlumlordDistrictDef> {
    for d in this.m_districts {
      if Equals(d.id, id) { return d; }
    }
    return null;
  }

  public func GetPropertyDef(id: CName) -> ref<SlumlordPropertyDef> {
    for p in this.m_properties {
      if Equals(p.id, id) { return p; }
    }
    return null;
  }

  public func GetState(id: CName) -> ref<SlumlordPropertyState> {
    for s in this.m_states {
      if Equals(s.id, id) { return s; }
    }
    return null;
  }

  // Rivals are named on the portal once V has met them. Watson: Oshima reveals himself on his call.
  public func IsRivalMet(districtId: CName) -> Bool {
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    if Equals(districtId, n"watson") {
      return IsDefined(boss) && boss.IsCallDone();
    }
    if Equals(districtId, n"santo_domingo") {
      return IsDefined(boss) && boss.IsFingerMet();
    }
    return false;
  }

  public func IsDistrictUnlocked(districtId: CName) -> Bool {
    let district = this.GetDistrictDef(districtId);
    return IsDefined(district) && this.GetStreetCred() >= district.streetCredRequired;
  }

  public func GetPrice(id: CName) -> Int32 {
    let def = this.GetPropertyDef(id);
    if !IsDefined(def) { return 0; }
    return SlumlordEconomy.Price(def, this.GetDistrictDef(def.districtId));
  }

  public func GetWeeklyRent(id: CName) -> Int32 {
    let def = this.GetPropertyDef(id);
    if !IsDefined(def) { return 0; }
    return SlumlordEconomy.WeeklyRent(def, this.GetDistrictDef(def.districtId), this.GetState(id));
  }

  public func GetUncollectedTotal() -> Int32 {
    let total = 0;
    for s in this.m_states {
      total += s.uncollected;
    }
    return total;
  }

  public func GetOwnedCount() -> Int32 {
    let count = 0;
    for s in this.m_states {
      if s.owned { count += 1; }
    }
    return count;
  }

  // District control, 0..100. Draft: share of the district's properties owned.
  public func GetDistrictControl(districtId: CName) -> Int32 {
    let total = 0;
    let owned = 0;
    for def in this.m_properties {
      if Equals(def.districtId, districtId) {
        total += 1;
        let state = this.GetState(def.id);
        if IsDefined(state) && state.owned { owned += 1; }
      }
    }
    if total == 0 { return 0; }
    return (owned * 100) / total;
  }

  public func GetLifetimeCollected() -> Int32 {
    return this.m_lifetimeCollected;
  }

  public func IsEmpireComplete() -> Bool {
    return this.m_empireComplete;
  }

  // ===================================================================== actions

  public func CanBuy(id: CName) -> SlumlordBuyResult {
    this.EnsureLoaded();
    let def = this.GetPropertyDef(id);
    let state = this.GetState(id);
    if !IsDefined(def) || !IsDefined(state) { return SlumlordBuyResult.UnknownProperty; }
    if state.owned { return SlumlordBuyResult.AlreadyOwned; }
    if !IsDefined(this.GetPlayer()) { return SlumlordBuyResult.NoPlayer; }
    if !this.IsDistrictUnlocked(def.districtId) { return SlumlordBuyResult.DistrictLocked; }
    if this.GetSpendingPower() < this.GetPrice(id) { return SlumlordBuyResult.NotEnoughMoney; }
    return SlumlordBuyResult.Ok;
  }

  public func Buy(id: CName) -> SlumlordBuyResult {
    let result = this.CanBuy(id);
    if !Equals(result, SlumlordBuyResult.Ok) { return result; }
    let def = this.GetPropertyDef(id);
    if !this.Spend(this.GetPrice(id), "Slumlord Realty", "Property purchase: " + def.displayName) { return SlumlordBuyResult.NotEnoughMoney; }
    this.TakeOwnership(id);
    return SlumlordBuyResult.Ok;
  }

  // Pays out all uncollected rent. Returns the amount paid.
  public func Collect() -> Int32 {
    this.Refresh();
    let total = this.GetUncollectedTotal();
    if total <= 0 { return 0; }
    let paying = 0;
    for s in this.m_states {
      if s.uncollected > 0 { paying += 1; }
      s.uncollected = 0;
      s.weeksUncollected = 0;
    }
    this.Earn(total, "Slumlord Realty", "Rent collected: " + IntToString(paying) + (paying == 1 ? " property" : " properties"));
    this.m_lifetimeCollected += total;
    this.RefreshPins();
    return total;
  }

  private func TakeOwnership(id: CName) -> Void {
    let def = this.GetPropertyDef(id);
    let state = this.GetState(id);
    state.owned = true;
    state.rank = 0;
    state.occupiedUnits = SlumlordEconomy.StartingOccupiedUnits(def);
    state.condition = SlumlordTuning.StartingCondition();
    state.uncollected = 0;
    state.weeksUncollected = 0;
    state.reportIn = 0;
    state.reportOut = 0;
    state.rankPoints = 0;
    state.jobsThisWeek = 0;
    ModLog(n"Slumlord", "Bought " + def.displayName);
    this.RefreshPins();
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    if IsDefined(boss) {
      boss.OnPropertyBought(def);
    }
    this.NotifyBosses();
    this.CheckEmpireComplete();
  }

  // Boss quests track how much of their district V owns ("Buy up <district> (n/5)").
  private func NotifyBosses() -> Void {
    let fight = SlumlordFight.GetInstance(this.GetGameInstance());
    if IsDefined(fight) {
      fight.OnPropertyChanged();
    }
    let finger = SlumlordFinger.GetInstance(this.GetGameInstance());
    if IsDefined(finger) {
      finger.OnPropertyChanged();
    }
  }

  // ---- alert text (Slumlord Realty) ----

  public func SetAlert(kind: Int32, property: CName, nameIndex: Int32, complaintIndex: Int32) -> Void {
    this.m_alertKind = kind;
    this.m_alertProperty = property;
    this.m_alertName = nameIndex;
    this.m_alertComplaint = complaintIndex;
  }

  public func BuildAlertText() -> String {
    this.EnsureLoaded();
    let def = this.GetPropertyDef(this.m_alertProperty);
    if this.m_alertKind != 1 || !IsDefined(def) { return "TENANT MOVED OUT - LEASE BROKEN!"; }
    let name = SlumlordNames.Get(this.m_alertName);
    let complaint = SlumlordConversationOvertime.Complaint(this.m_alertComplaint);
    if def.commercial {
      return "BUSINESS MOVED OUT - LEASE BROKEN!\n" + name + " closed up shop at " + def.displayName + " in a huff, complaining " + complaint;
    }
    return "TENANT MOVED OUT - LEASE BROKEN!\n" + name + " moved out of " + def.displayName + " in a huff, complaining " + complaint;
  }

  private func CheckEmpireComplete() -> Void {
    if this.m_empireComplete { return; }
    if this.GetOwnedCount() < ArraySize(this.m_properties) { return; }
    this.m_empireComplete = true;
    // Phase 5 hook: Chairman Mao contact + The Landlord Special.
    this.ShowMessage("Every property in Night City is yours. Someone wants to meet you.");
    ModLog(n"Slumlord", "Empire complete.");
  }

  // ===================================================================== map pins

  // Draft: one vanilla pin per captured position in an unlocked district.
  // Phase 1b replaces the vanilla icon with the design-system pin atlas
  // (listing / owned by rank / rent / trouble).
  public func RefreshPins() -> Void {
    let mappins = GameInstance.GetMappinSystem(this.GetGameInstance());
    for pinId in this.m_pinIds {
      mappins.UnregisterMappin(pinId);
    }
    ArrayClear(this.m_pinIds);
    for def in this.m_properties {
      if SlumlordPositions.Has(def.id) && this.IsDistrictUnlocked(def.districtId) {
        let data: MappinData;
        data.mappinType = t"Mappins.DefaultStaticMappin";
        data.variant = gamedataMappinVariant.Zzz05_ApartmentToPurchaseVariant; // drawn over with our pin (Pins.reds)
        data.scriptData = SlumlordPins.Data(this.GetState(def.id));
        data.active = true;
        data.debugCaption = "Slumlord " + NameToString(def.id);
        data.visibleThroughWalls = false;
        ArrayPush(this.m_pinIds, mappins.RegisterMappin(data, SlumlordPositions.Get(def.id)));
      }
    }
  }

  // ===================================================================== contractors (Contractors.reds)

  public func GetContractors() -> array<ref<SlumlordContractorDef>> {
    this.EnsureLoaded();
    return this.m_contractors;
  }

  public func GetContractorDef(id: CName) -> ref<SlumlordContractorDef> {
    for c in this.m_contractors {
      if Equals(c.id, id) { return c; }
    }
    return null;
  }

  // District Contractors come with their district's Street Cred gate; the rest are unlocked by quests or fixers.
  public func IsContractorAvailable(c: ref<SlumlordContractorDef>) -> Bool {
    if !IsDefined(c) { return false; }
    if IsNameValid(c.districtId) {
      return this.IsDistrictUnlocked(c.districtId);
    }
    return ArrayContains(this.m_unlockedContractors, c.id);
  }

  public func UnlockContractor(id: CName) -> Void {
    if !ArrayContains(this.m_unlockedContractors, id) {
      ArrayPush(this.m_unlockedContractors, id);
    }
  }

  // Points needed to rank this property up from its current rank (0 at S).
  public func GetRankPointsNeeded(id: CName) -> Int32 {
    let def = this.GetPropertyDef(id);
    let state = this.GetState(id);
    if !IsDefined(def) || !IsDefined(state) || state.rank >= SlumlordTuning.MaxRank() { return 0; }
    let price = Cast<Float>(SlumlordEconomy.Price(def, this.GetDistrictDef(def.districtId)));
    return Max(1, RoundF(price * SlumlordTuning.RankBarShare(state.rank)));
  }

  public func GetJobsLeft(id: CName) -> Int32 {
    let state = this.GetState(id);
    if !IsDefined(state) { return 0; }
    return Max(0, SlumlordTuning.JobsPerRentDay() - state.jobsThisWeek);
  }

  public func CanHire(propertyId: CName, contractorId: CName) -> SlumlordHireResult {
    this.EnsureLoaded();
    let def = this.GetPropertyDef(propertyId);
    let state = this.GetState(propertyId);
    let c = this.GetContractorDef(contractorId);
    if !IsDefined(def) || !IsDefined(state) || !IsDefined(c) { return SlumlordHireResult.UnknownProperty; }
    if !state.owned { return SlumlordHireResult.NotOwned; }
    if state.rank >= SlumlordTuning.MaxRank() { return SlumlordHireResult.MaxRank; }
    if state.jobsThisWeek >= SlumlordTuning.JobsPerRentDay() { return SlumlordHireResult.JobLimit; }
    if !this.IsContractorAvailable(c) { return SlumlordHireResult.ContractorLocked; }
    if !IsDefined(this.GetPlayer()) { return SlumlordHireResult.NoPlayer; }
    if this.GetSpendingPower() < SlumlordTuning.ContractorFee(c.stars) { return SlumlordHireResult.NotEnoughMoney; }
    return SlumlordHireResult.Progress;
  }

  // One Contractor job: pay the fee, add points; a full bar raises the rank by one (excess points are lost).
  public func Hire(propertyId: CName, contractorId: CName) -> SlumlordHireResult {
    let result = this.CanHire(propertyId, contractorId);
    if !Equals(result, SlumlordHireResult.Progress) { return result; }
    let def = this.GetPropertyDef(propertyId);
    let state = this.GetState(propertyId);
    let c = this.GetContractorDef(contractorId);
    if !this.Spend(SlumlordTuning.ContractorFee(c.stars), c.crew, "Renovation: " + def.displayName) { return SlumlordHireResult.NotEnoughMoney; }
    let needed = this.GetRankPointsNeeded(propertyId);
    state.jobsThisWeek += 1;
    state.rankPoints += SlumlordContractors.JobPoints(c, def);
    if state.rankPoints >= needed {
      state.rank += 1;
      state.rankPoints = 0;
      ModLog(n"Slumlord", def.displayName + " renovated by " + c.crew + ": rank " + SlumlordEconomy.RankLetter(state.rank));
      this.RefreshPins();
      return SlumlordHireResult.RankedUp;
    }
    return SlumlordHireResult.Progress;
  }

  // ===================================================================== debug (called from the CET tool)

  public func Debug_ForceRentDay() -> Int32 {
    this.EnsureLoaded();
    this.m_initialized = true;
    this.m_lastRentWeek = this.CurrentWeek() - 1;
    this.Refresh();
    return this.GetUncollectedTotal();
  }

  public func Debug_BuyFree(id: CName) -> Bool {
    this.EnsureLoaded();
    let state = this.GetState(id);
    if !IsDefined(state) || state.owned { return false; }
    this.TakeOwnership(id);
    return true;
  }

  // Un-own a property (testing the Watson trigger: release one, reset the fight, buy it again).
  public func Debug_Release(id: CName) -> Bool {
    this.EnsureLoaded();
    let state = this.GetState(id);
    if !IsDefined(state) || !state.owned { return false; }
    state.owned = false;
    state.rank = 0;
    state.occupiedUnits = 0;
    state.uncollected = 0;
    state.weeksUncollected = 0;
    state.reportIn = 0;
    state.reportOut = 0;
    state.rankPoints = 0;
    state.jobsThisWeek = 0;
    this.RefreshPins();
    this.NotifyBosses();
    return true;
  }

  public func Debug_SetRank(id: CName, rank: Int32) -> Bool {
    let state = this.GetState(id);
    if !IsDefined(state) { return false; }
    state.rank = Clamp(rank, 0, SlumlordTuning.MaxRank());
    state.rankPoints = 0;
    this.RefreshPins();
    return true;
  }

  // Makes the quest/fixer Contractors (The Architect, Oshima) available.
  public func Debug_UnlockContractors() -> Void {
    this.EnsureLoaded();
    for c in this.m_contractors {
      if !IsNameValid(c.districtId) {
        this.UnlockContractor(c.id);
      }
    }
  }

  // Clears every property's Contractor job count for this week.
  public func Debug_ResetJobs() -> Void {
    for s in this.m_states {
      s.jobsThisWeek = 0;
    }
  }

  public func Debug_ResetAll() -> Void {
    ArrayClear(this.m_states);
    this.m_lifetimeCollected = 0;
    this.m_empireComplete = false;
    this.m_initialized = true;
    this.m_lastRentWeek = this.CurrentWeek();
    this.EnsureLoaded();
    this.RefreshPins();
  }

  public func Debug_Dump() -> String {
    this.EnsureLoaded();
    let out = "SLUMLORD  day " + IntToString(this.CurrentDay())
      + "  rent day in " + IntToString(this.DaysUntilRentDay()) + "d"
      + "  street cred " + IntToString(this.GetStreetCred())
      + "  owned " + IntToString(this.GetOwnedCount()) + "/" + IntToString(ArraySize(this.m_properties))
      + "  uncollected " + SlumlordEconomy.FormatMoney(this.GetUncollectedTotal())
      + "  lifetime " + SlumlordEconomy.FormatMoney(this.m_lifetimeCollected)
      + "\n" + SlumlordBank.Describe(this.GetGameInstance());
    for d in this.m_districts {
      out = out + "\n" + d.displayName
        + (this.IsDistrictUnlocked(d.id) ? "" : " [LOCKED: cred " + IntToString(d.streetCredRequired) + "]")
        + "  control " + IntToString(this.GetDistrictControl(d.id)) + "%";
      for p in this.m_properties {
        if Equals(p.districtId, d.id) {
          let s = this.GetState(p.id);
          out = out + "\n  " + NameToString(p.id) + "  " + p.displayName
            + "  price " + SlumlordEconomy.FormatMoney(this.GetPrice(p.id));
          if IsDefined(s) && s.owned {
            out = out + "  OWNED rank " + SlumlordEconomy.RankLetter(s.rank)
              + "  " + IntToString(s.occupiedUnits) + "/" + IntToString(p.units) + " units"
              + "  weekly " + SlumlordEconomy.FormatMoney(this.GetWeeklyRent(p.id))
              + "  waiting " + SlumlordEconomy.FormatMoney(s.uncollected)
              + "  bar " + IntToString(s.rankPoints) + "/" + IntToString(this.GetRankPointsNeeded(p.id))
              + "  jobs " + IntToString(s.jobsThisWeek) + "/" + IntToString(SlumlordTuning.JobsPerRentDay());
          }
          if !SlumlordPositions.Has(p.id) {
            out = out + "  (no pin position)";
          }
        }
      }
    }
    return out;
  }
}

public class SlumlordTickCallback extends DelayCallback {
  public let system: wref<SlumlordSystem>;

  public func Call() -> Void {
    let sys = this.system;
    if IsDefined(sys) {
      sys.OnTick();
    }
  }
}
