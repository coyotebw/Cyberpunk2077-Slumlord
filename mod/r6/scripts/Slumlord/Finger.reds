// Santo Domingo boss arc (design doc 4.9): Quentin Finger, owner of the Las Palapas Motel. Quest "Won't Bite".
//
//  1 Threat call after V's first Santo Domingo purchase (Boss.reds) -> quest starts: "Buy up Santo Domingo (n/5)".
//  2 Lease broken: from the call until the win, each rent day every owned Santo Domingo property with tenants
//    has a 20% chance that Finger's people drive one out, at a random hour within the next week. Slumlord
//    Realty texts at once (Tenants.reds draws the live text).
//  3 All of Santo Domingo owned -> Finger's goading call ("I stole somethin' of yours").
//  4 "Meet Finger at the Las Palapas Motel", at night only (20:00-05:00; "Wait until night" by day).
//    The motel scene (Finger, 6th Street goons, a Yaiba Kusanagi that isn't V's) is NOT BUILT YET: it needs
//    positions captured at Las Palapas and Andrew's recordings. Debug "Win" stands in for it.
//  5 Win: Santo Domingo dominated, lease-broken events stop, the Kusanagi goes into V's garage, and the
//    goons' services are owed to V as Muscle (staff, Phase 2).
module Slumlord

public abstract class SlumlordWontBite {
  public static func Quest() -> String { return "quests/minor_quest/slumlord_wont_bite"; }
  public static func Phase() -> String { return SlumlordWontBite.Quest() + "/slumlord_wb_phase"; }
  public static func District() -> CName { return n"santo_domingo"; }
  public static func HarassChance() -> Float { return 0.20; }
  public static func NightStartHour() -> Int32 { return 20; }
  public static func NightEndHour() -> Int32 { return 5; }
  public static func GoadDelaySeconds() -> Float { return 30.0; }
  public static func DoneFact() -> String { return "slumlord_sd_boss_done"; }
  public static func RewardXP() -> Int32 { return 1000; }
  // Yaiba Kusanagi CT-3X, player version (to confirm in game).
  public static func BikeRecord() -> String { return "Vehicle.v_sportbike1_yaiba_kusanagi_player"; }
  // Motel scene, for when it is built: 6th Street records (to confirm in game).
  public static func Goons() -> array<TweakDBID> {
    return [t"Character.sixthstreet_hooligan_ranged1_saratoga_wa", t"Character.sixthstreet_hooligan_ranged1_nova_wa",
            t"Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare"];
  }

  // Drafts (design doc 4.9). Each follows "...moved out in a huff, complaining ".
  public static func Complaints() -> array<String> {
    return [
      "that they got robbed on the stairs. Twice.",
      "that a car chased them all the way down Wollesen St.",
      "that there's always gangoons out front.",
      "that someone keyed LEAVE into their door.",
      "that a guy in a Las Palapas jacket followed them home.",
      "that the power's been cut every night this week.",
      "that somebody left a dead rat in their mailbox. With a bow on it.",
      "that the new security guy asked them for protection money."
    ];
  }

  public static func ComplaintCount() -> Int32 {
    let all = SlumlordWontBite.Complaints();
    return ArraySize(all);
  }

  public static func Complaint(index: Int32) -> String {
    let all = SlumlordWontBite.Complaints();
    if index < 0 || index >= ArraySize(all) { return all[0]; }
    return all[index];
  }
}

public class SlumlordFinger extends ScriptableSystem {
  private persistent let m_stage: Int32;              // 0 not started, 1 buying up, 2 goading call due, 3 meet at the motel, 5 won
  private persistent let m_eventProps: array<CName>;  // pending lease-broken events (parallel arrays)
  private persistent let m_eventDue: array<Int32>;    // absolute game hour (day * 24 + hour)
  private persistent let m_eventName: array<Int32>;
  private persistent let m_eventComplaint: array<Int32>;
  private persistent let m_muscleOwed: Bool;          // the goons' services, for when Muscle staff exist
  private persistent let m_bikeGiven: Bool;

  public static func GetInstance(game: GameInstance) -> ref<SlumlordFinger> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordFinger") as SlumlordFinger;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    if this.m_stage == 3 {
      this.UpdateNight();
    }
  }

  public func IsWon() -> Bool { return this.m_stage == 5; }
  public func IsMuscleOwed() -> Bool { return this.m_muscleOwed; }
  private func HarassActive() -> Bool { return this.m_stage >= 1 && this.m_stage <= 3; }

  private func NowHour() -> Int32 {
    let t = GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTime();
    return GameTime.Days(t) * 24 + GameTime.Hours(t);
  }

  private func IsNight() -> Bool {
    let hour = GameTime.Hours(GameInstance.GetTimeSystem(this.GetGameInstance()).GetGameTime());
    return hour >= SlumlordWontBite.NightStartHour() || hour < SlumlordWontBite.NightEndHour();
  }

  // ---- stage 1: the threat call is over, the quest starts ----

  public func OnThreatCallDone() -> Void {
    if this.m_stage != 0 { return; }
    let game = this.GetGameInstance();
    if !SlumlordJournal.Installed(game) {
      SlumlordUi.Log("Won't Bite: journal missing (Slumlord.archive not installed or outdated)");
    }
    this.m_stage = 1;
    SlumlordJournal.Set(game, SlumlordWontBite.Quest(), "gameJournalQuest", gameJournalEntryState.Active, true);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest() + "/slumlord_wb_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Active, false);
    SlumlordUi.Log("Won't Bite: started after Finger's call");
    this.OnPropertyChanged();
  }

  // Every purchase and release (System.reds).
  public func OnPropertyChanged() -> Void {
    if this.m_stage != 1 { return; }
    let game = this.GetGameInstance();
    let done = SlumlordBuyUp.Update(game, SlumlordWontBite.Phase(), "slumlord_wb_buy_", SlumlordWontBite.District(), true);
    if done {
      this.m_stage = 2;
      SlumlordUi.Log("Won't Bite: Santo Domingo owned, Finger's goading call due");
      let boss = SlumlordBoss.GetInstance(game);
      if IsDefined(boss) {
        boss.RequestFingerGoad(SlumlordWontBite.GoadDelaySeconds());
      }
    }
  }

  // ---- stage 3: the goading call is over, meet him at the motel tonight ----

  public func OnGoadCallDone() -> Void {
    if this.m_stage != 2 { return; }
    let game = this.GetGameInstance();
    this.m_stage = 3;
    SlumlordJournal.Set(game, SlumlordWontBite.Quest() + "/slumlord_wb_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest() + "/slumlord_wb_desc_motel", "gameJournalQuestDescription", gameJournalEntryState.Active, true);
    this.UpdateNight();
  }

  // "Wait until night" by day, "Meet Finger at the Las Palapas Motel" at night.
  private func UpdateNight() -> Void {
    if this.m_stage != 3 { return; }
    let game = this.GetGameInstance();
    let night = this.IsNight();
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_wait", "gameJournalQuestObjective", night ? gameJournalEntryState.Inactive : gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_motel", "gameJournalQuestObjective", night ? gameJournalEntryState.Active : gameJournalEntryState.Inactive, false);
    SlumlordBuyUp.Track(game, SlumlordWontBite.Phase() + (night ? "/slumlord_wb_motel" : "/slumlord_wb_wait"));
    // TODO motel scene: map pin (marker node at Las Palapas), spawn Finger, goons and the bike at night.
  }

  // ---- lease broken ----

  // SlumlordSystem.Refresh, once per refresh that processed rent days (the last one numbers the rolls).
  public func OnRentDay(rentDay: Int32) -> Void {
    if !this.HarassActive() { return; }
    let sys = SlumlordSystem.GetInstance(this.GetGameInstance());
    if !IsDefined(sys) { return; }
    let now = this.NowHour();
    for def in sys.GetProperties() {
      let state = sys.GetState(def.id);
      if Equals(def.districtId, SlumlordWontBite.District()) && IsDefined(state) && state.owned && state.occupiedUnits > 0 {
        if SlumlordTenants.Roll(def.id, rentDay, 900) < SlumlordWontBite.HarassChance() {
          let due = now + 1 + FloorF(SlumlordTenants.Roll(def.id, rentDay, 901) * 166.0);
          let name = SlumlordNames.RandomIndex(SlumlordTenants.Roll(def.id, rentDay, 902));
          let complaint = FloorF(SlumlordTenants.Roll(def.id, rentDay, 903) * Cast<Float>(SlumlordWontBite.ComplaintCount()));
          this.AddEvent(def.id, due, name, complaint);
        }
      }
    }
  }

  private func AddEvent(id: CName, due: Int32, name: Int32, complaint: Int32) -> Void {
    ArrayPush(this.m_eventProps, id);
    ArrayPush(this.m_eventDue, due);
    ArrayPush(this.m_eventName, name);
    ArrayPush(this.m_eventComplaint, complaint);
    SlumlordUi.Log("Won't Bite: lease broken at " + NameToString(id) + " due in " + IntToString(due - this.NowHour()) + " h");
  }

  private func RemoveEvent(i: Int32) -> Void {
    ArrayErase(this.m_eventProps, i);
    ArrayErase(this.m_eventDue, i);
    ArrayErase(this.m_eventName, i);
    ArrayErase(this.m_eventComplaint, i);
  }

  // SlumlordSystem's 30 s tick. At most one event per tick, so several texts don't arrive at once.
  public func OnSystemTick() -> Void {
    if this.m_stage == 3 {
      this.UpdateNight();
    }
    if !this.HarassActive() || ArraySize(this.m_eventProps) == 0 { return; }
    let now = this.NowHour();
    let i = 0;
    while i < ArraySize(this.m_eventProps) {
      if this.m_eventDue[i] <= now {
        this.Fire(i);
        this.RemoveEvent(i);
        return;
      }
      i += 1;
    }
  }

  private func Fire(i: Int32) -> Void {
    let game = this.GetGameInstance();
    let sys = SlumlordSystem.GetInstance(game);
    if !IsDefined(sys) { return; }
    let id = this.m_eventProps[i];
    let state = sys.GetState(id);
    if !IsDefined(state) || !state.owned || state.occupiedUnits <= 0 { return; }
    state.occupiedUnits -= 1;
    state.reportOut += 1;
    sys.SetAlert(1, id, this.m_eventName[i], this.m_eventComplaint[i]);
    SlumlordTenantReport.SendAlert(game);
    SlumlordUi.Log("Won't Bite: lease broken at " + NameToString(id));
  }

  // ---- stage 5: the win (stand-in until the motel scene exists) ----

  public func Win() -> Void {
    if this.m_stage == 5 { return; }
    let game = this.GetGameInstance();
    this.m_stage = 5;
    ArrayClear(this.m_eventProps);
    ArrayClear(this.m_eventDue);
    ArrayClear(this.m_eventName);
    ArrayClear(this.m_eventComplaint);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_wait", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_motel", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_goons", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest(), "gameJournalQuest", gameJournalEntryState.Succeeded, true);
    GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordWontBite.DoneFact(), 1);
    this.m_muscleOwed = true;
    this.GiveBike();
    RPGManager.AwardExperienceInstantly(GetPlayer(game), SlumlordWontBite.RewardXP(), gamedataProficiencyType.Level);
    SlumlordUi.Log("Won't Bite: won, Santo Domingo dominated");
  }

  // The Kusanagi that isn't V's: V keeps it, in the garage.
  private func GiveBike() -> Void {
    if this.m_bikeGiven { return; }
    this.m_bikeGiven = GameInstance.GetVehicleSystem(this.GetGameInstance()).EnablePlayerVehicle(SlumlordWontBite.BikeRecord(), true, false);
    SlumlordUi.Log("Won't Bite: Kusanagi to garage " + (this.m_bikeGiven ? "ok" : "FAILED (check the record name)"));
  }

  // ---- debug (CET tool) ----

  public func Debug_StartQuest() -> Void {
    this.m_stage = 0;
    this.OnThreatCallDone();
  }

  // A lease-broken event at the first owned Santo Domingo property with tenants, due now.
  public func Debug_HarassNow() -> String {
    let sys = SlumlordSystem.GetInstance(this.GetGameInstance());
    if !IsDefined(sys) { return "no system"; }
    if !this.HarassActive() { return "quest not running (stage " + IntToString(this.m_stage) + ")"; }
    for def in sys.GetProperties() {
      let state = sys.GetState(def.id);
      if Equals(def.districtId, SlumlordWontBite.District()) && IsDefined(state) && state.owned && state.occupiedUnits > 0 {
        let r = RandF();
        this.AddEvent(def.id, this.NowHour(), SlumlordNames.RandomIndex(r), FloorF(RandF() * Cast<Float>(SlumlordWontBite.ComplaintCount())));
        return "queued at " + def.displayName + " (fires on the next tick, up to 30 s)";
      }
    }
    return "no owned Santo Domingo property with tenants";
  }

  public func Debug_Win() -> Void {
    this.Win();
  }

  public func Debug_Reset() -> Void {
    let game = this.GetGameInstance();
    this.m_stage = 0;
    this.m_muscleOwed = false;
    this.m_bikeGiven = false;
    ArrayClear(this.m_eventProps);
    ArrayClear(this.m_eventDue);
    ArrayClear(this.m_eventName);
    ArrayClear(this.m_eventComplaint);
    SlumlordBuyUp.Clear(game, SlumlordWontBite.Phase(), "slumlord_wb_buy_");
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_wait", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_motel", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase() + "/slumlord_wb_goons", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest() + "/slumlord_wb_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest() + "/slumlord_wb_desc_motel", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordWontBite.Quest(), "gameJournalQuest", gameJournalEntryState.Inactive, false);
    GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordWontBite.DoneFact(), 0);
    let boss = SlumlordBoss.GetInstance(game);
    if IsDefined(boss) {
      boss.Debug_ResetFinger();
    }
  }

  public func Debug_State() -> String {
    let total: Int32;
    let owned = SlumlordBuyUp.Owned(this.GetGameInstance(), SlumlordWontBite.District(), total);
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    return "santo " + IntToString(owned) + "/" + IntToString(total) + " stage=" + IntToString(this.m_stage)
      + " night=" + (this.IsNight() ? "yes" : "no")
      + " pending events=" + IntToString(ArraySize(this.m_eventProps))
      + " muscle owed=" + (this.m_muscleOwed ? "yes" : "no") + " bike=" + (this.m_bikeGiven ? "yes" : "no")
      + " | " + (IsDefined(boss) ? boss.Debug_State() : "no boss system");
  }
}
