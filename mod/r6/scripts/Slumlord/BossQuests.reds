// Shared pieces of the district boss quests (design doc 1 "Boss quests", 4.8, 4.9).
// Every boss quest starts right after the boss's first call, with an objective to buy up the district.
// The game reads objective counters from engine code that scripts cannot set, so "Buy up <district> (n/5)"
// is six static objectives, <prefix>0 .. <prefix>5 (tools/journal/add_boss_quests.py); only the one
// matching the number of properties owned is shown, and <prefix>5 is marked done when V owns them all.
module Slumlord

public abstract class SlumlordBuyUp {

  public static func Owned(game: GameInstance, districtId: CName, out total: Int32) -> Int32 {
    let owned = 0;
    total = 0;
    let sys = SlumlordSystem.GetInstance(game);
    if !IsDefined(sys) { return 0; }
    for def in sys.GetProperties() {
      if Equals(def.districtId, districtId) {
        total += 1;
        let state = sys.GetState(def.id);
        if IsDefined(state) && state.owned { owned += 1; }
      }
    }
    return owned;
  }

  public static func Complete(game: GameInstance, districtId: CName) -> Bool {
    let total: Int32;
    let owned = SlumlordBuyUp.Owned(game, districtId, total);
    return total > 0 && owned == total;
  }

  // Shows the objective for the current count. Returns true when the district is fully owned.
  public static func Update(game: GameInstance, phasePath: String, prefix: String, districtId: CName, track: Bool) -> Bool {
    let total: Int32;
    let owned = SlumlordBuyUp.Owned(game, districtId, total);
    let done = total > 0 && owned >= total;
    let shown = done ? 5 : Clamp(owned, 0, 4);
    let i = 0;
    while i <= 5 {
      let path = phasePath + "/" + prefix + IntToString(i);
      let state = gameJournalEntryState.Inactive;
      if i == shown {
        state = done ? gameJournalEntryState.Succeeded : gameJournalEntryState.Active;
      }
      SlumlordJournal.Set(game, path, "gameJournalQuestObjective", state, false);
      i += 1;
    }
    if track && !done {
      SlumlordBuyUp.Track(game, phasePath + "/" + prefix + IntToString(shown));
    }
    return done;
  }

  public static func Clear(game: GameInstance, phasePath: String, prefix: String) -> Void {
    let i = 0;
    while i <= 5 {
      SlumlordJournal.Set(game, phasePath + "/" + prefix + IntToString(i), "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
      i += 1;
    }
  }

  public static func Track(game: GameInstance, objectivePath: String) -> Void {
    let jm = GameInstance.GetJournalManager(game);
    let entry = jm.GetEntryByString(objectivePath, "gameJournalQuestObjective");
    if IsDefined(entry) {
      jm.TrackEntry(entry);
    }
  }
}
