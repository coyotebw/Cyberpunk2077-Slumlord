// Tenant arrivals, move-outs and the weekly tenant report text (design doc 4.3).
//
// Each rent day, per owned property: rent for the week just ended is paid on current occupancy
// (System.reds), then tenants move out, then new tenants arrive.
//  - Arrivals per building per week: SlumlordTuning.ArrivalsPerWeek(rank) x district safety multiplier.
//    The fraction is a roll: 0.4 means a 40% chance of one tenant that week. Rank S fills every empty unit.
//  - Move-outs: each tenant rolls SlumlordTuning.MoveOutChance(rank) x safety multiplier.
//    Commercial (business) tenants roll CommercialMoveOutChance(rank) only; safety does not apply.
// Rolls are seeded by property id, rent-day number (saved) and roll number, so reloading a save gives the same result.
//
// The report is one journal message (contact "Slumlord Realty", Slumlord.archive), re-sent each rent day.
// Its stored text is only a fallback ("Your weekly tenant report is ready."): the conversation view and
// the incoming-message pop-up draw the live report instead (hooks at the end of this file).
module Slumlord

public abstract class SlumlordTenants {

  // Deterministic roll in [0, 1) for this property, week and roll number.
  // TweakDBID's low 32 bits are a CRC32 of the string: spread checked in tools/sim/crc_rolls.py.
  public static func Roll(id: CName, week: Int32, salt: Int32) -> Float {
    let key = "slumlord.tenants." + NameToString(id) + "." + IntToString(week) + "." + IntToString(salt);
    let h = Cast<Int32>(TDBID.ToNumber(TDBID.Create(key)));
    let r = ((h % 10000) + 10000) % 10000;
    return Cast<Float>(r) / 10000.0;
  }

  public static func MoveOutChance(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>, rank: Int32) -> Float {
    if def.commercial {
      return SlumlordTuning.CommercialMoveOutChance(rank);
    }
    return SlumlordTuning.MoveOutChance(rank) * SlumlordTuning.SafetyMoveOutMultiplier(district.safety);
  }

  // Expected new tenants per week; negative = fill every empty unit (rank S).
  public static func ArrivalRate(district: ref<SlumlordDistrictDef>, rank: Int32) -> Float {
    let base = SlumlordTuning.ArrivalsPerWeek(rank);
    if base < 0.0 { return base; }
    return base * SlumlordTuning.SafetyArrivalMultiplier(district.safety);
  }

  // One week of tenant changes for one owned property. Adds to the state's report counters.
  public static func StepWeek(def: ref<SlumlordPropertyDef>, district: ref<SlumlordDistrictDef>, state: ref<SlumlordPropertyState>, week: Int32) -> Void {
    if !IsDefined(def) || !IsDefined(district) || !IsDefined(state) || !state.owned { return; }

    // Move-outs: one roll per tenant (rolls 100, 101, ...).
    let leaveChance = SlumlordTenants.MoveOutChance(def, district, state.rank);
    let left = 0;
    let i = 0;
    while i < state.occupiedUnits {
      if SlumlordTenants.Roll(state.id, week, 100 + i) < leaveChance {
        left += 1;
      }
      i += 1;
    }
    state.occupiedUnits -= left;

    // Arrivals (roll 1).
    let vacant = def.units - state.occupiedUnits;
    let arrived = 0;
    if vacant > 0 {
      let rate = SlumlordTenants.ArrivalRate(district, state.rank);
      if rate < 0.0 {
        arrived = vacant;
      } else {
        let whole = FloorF(rate);
        arrived = whole;
        if SlumlordTenants.Roll(state.id, week, 1) < rate - Cast<Float>(whole) {
          arrived += 1;
        }
        arrived = Min(arrived, vacant);
      }
    }
    state.occupiedUnits += arrived;

    state.reportIn += arrived;
    state.reportOut += left;
  }
}

public abstract class SlumlordTenantReport {
  public static func Contact() -> String { return "contacts/slumlord_realty"; }
  public static func Thread() -> String { return SlumlordTenantReport.Contact() + "/slumlord_realty_reports"; }
  public static func MessageId() -> String { return "slumlord_realty_report"; }
  public static func Message() -> String { return SlumlordTenantReport.Thread() + "/" + SlumlordTenantReport.MessageId(); }

  // Re-sends the report message: inactive, then active with a notification.
  // Does nothing when Slumlord.archive (with the contact) is not installed.
  public static func Send(game: GameInstance) -> Void {
    let jm = GameInstance.GetJournalManager(game);
    if !IsDefined(jm.GetEntryByString(SlumlordTenantReport.Thread(), "gameJournalPhoneConversation")) {
      ModLog(n"Slumlord", "Tenant report: contact missing (Slumlord.archive not installed or outdated).");
      return;
    }
    SlumlordJournal.Set(game, SlumlordTenantReport.Contact(), "gameJournalContact", gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordTenantReport.Thread(), "gameJournalPhoneConversation", gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordTenantReport.Message(), "gameJournalPhoneMessage", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordTenantReport.Message(), "gameJournalPhoneMessage", gameJournalEntryState.Active, true);
  }

  public static func IsReport(entry: wref<JournalEntry>) -> Bool {
    return IsDefined(entry) && Equals(entry.GetId(), SlumlordTenantReport.MessageId());
  }

  public static func Text(game: GameInstance) -> String {
    let system = SlumlordSystem.GetInstance(game);
    if !IsDefined(system) { return "Your weekly tenant report is ready."; }
    return system.BuildTenantReport();
  }
}

public abstract class SlumlordTenantReportLine {
  // "Harbor Safehouse: +2, -1" or, for a business, "Capitan Caliente: business moved out".
  public static func For(def: ref<SlumlordPropertyDef>, movedIn: Int32, movedOut: Int32) -> String {
    if def.commercial {
      if movedIn > 0 && movedOut > 0 { return def.displayName + ": business replaced"; }
      if movedOut > 0 { return def.displayName + ": business moved out"; }
      return def.displayName + ": new business moved in";
    }
    let parts = "";
    if movedIn > 0 {
      parts = "+" + IntToString(movedIn);
    }
    if movedOut > 0 {
      parts = parts + (StrLen(parts) > 0 ? ", " : "") + "-" + IntToString(movedOut);
    }
    return def.displayName + ": " + parts;
  }
}

// Conversation view: draw the live report in place of the stored fallback text.
@wrapMethod(MessangerItemRenderer)
protected func OnJournalEntryUpdated(entry: wref<JournalEntry>, extraData: ref<IScriptable>) -> Void {
  wrappedMethod(entry, extraData);
  if SlumlordTenantReport.IsReport(entry) {
    inkTextRef.SetText(this.m_labelPathRef, SlumlordTenantReport.Text(GetGameInstance()));
  }
}

// Incoming-message pop-up: same, shortened the way the game shortens long texts.
@wrapMethod(PhoneMessageNotificationsGameController)
private final func ShowNotification() -> Void {
  wrappedMethod();
  if IsDefined(this.m_data) && SlumlordTenantReport.IsReport(this.m_data.journalEntry) {
    let text = SlumlordTenantReport.Text(GetGameInstance());
    if this.m_maxMessageSize > 0 && StrLen(text) > this.m_maxMessageSize {
      text = StrLeft(text, this.m_maxMessageSize) + "...";
    }
    inkTextRef.SetText(this.m_text, text);
  }
}
