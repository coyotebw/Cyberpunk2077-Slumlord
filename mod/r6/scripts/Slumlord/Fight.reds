// Watson boss arc (design doc 4.8), beats 2-4: Karl's texts, the Harbor Safehouse confrontation, the win.
// Quest "Million Dollar Baby" (journal id slumlord_final_cut, kept so saves carry over).
//
// Texts, quest and objectives are journal entries from Slumlord.archive (slumlord\journal\slumlord.journal,
// texts in slumlord\localization\en-us.json, both loaded by Slumlord.archive.xl), revealed from here with
// JournalManager.ChangeEntryState, the way quest nodes do it. The map pin is a journal pin on a marker node.
//
// The confrontation itself is the game's own quest files since 2026-11-22 (tools/quest/make_scenes.py, design
// doc 13): slumlord\quest\slumlord_harbor.questphase spawns Oshima and four Maelstromers from communities on
// AI spots (knocking, welding, smoking, arguing; Oshima arms crossed), clears the crowd, plays the talk scene,
// turns the gang hostile, has Oshima shout and leave, and waits until the gang is down. This system is the bridge,
// through quest facts:
//   slumlord_fc_ready  set here: 1 while the quest is at the Safehouse stage -> the phase may start
//   slumlord_fc_scene  read here: 1 while the encounter is up -> remove the vanilla Maelstromers at the door
//   slumlord_fc_fight  read here: 1 fighting (objectives switch), 2 the gang is down
//   slumlord_fc_fled   read here: 1 when Oshima shouts and runs -> his Sandevistan sprint
//   slumlord_fc_won    read here: 1 -> Win() (journal, XP, Oshima unlocked as a contractor, Karl's thanks)
//   slumlord_fc_abort  set here: 1 ends the encounter (debug reset)
//   slumlord_fc_tries  quest: casts that failed to spawn in a row (3: the phase waits until V leaves); reset here
// What stays in script: Oshima's Sandevistan dashes during the fight and his sprint away (the game's NPC
// Sandevistan time dilation, ease curves and FX names, driven from here), and removing the vanilla gang.
module Slumlord

public abstract class SlumlordJournal {
  public static func Quest() -> String { return "quests/minor_quest/slumlord_final_cut"; }
  public static func Phase() -> String { return SlumlordJournal.Quest() + "/slumlord_fc_phase"; }
  public static func Karl() -> String { return "contacts/slumlord_karl"; }
  public static func Thread() -> String { return SlumlordJournal.Karl() + "/slumlord_karl_harbor"; }

  public static func Set(game: GameInstance, path: String, cls: String, state: gameJournalEntryState, notify: Bool) -> Void {
    GameInstance.GetJournalManager(game).ChangeEntryState(path, cls, state, notify ? JournalNotifyOption.Notify : JournalNotifyOption.DoNotNotify);
  }

  public static func Objective(game: GameInstance, id: String, state: gameJournalEntryState) -> Void {
    SlumlordJournal.Set(game, SlumlordJournal.Phase() + "/" + id, "gameJournalQuestObjective", state, false);
  }

  public static func Track(game: GameInstance, id: String) -> Void {
    let jm = GameInstance.GetJournalManager(game);
    let entry = jm.GetEntryByString(SlumlordJournal.Phase() + "/" + id, "gameJournalQuestObjective");
    if IsDefined(entry) {
      jm.TrackEntry(entry);
    }
  }

  // False when Slumlord.archive (with its journal) is not installed.
  public static func Installed(game: GameInstance) -> Bool {
    let jm = GameInstance.GetJournalManager(game);
    return IsDefined(jm.GetEntryByString(SlumlordJournal.Thread(), "gameJournalPhoneConversation"));
  }
}

public class SlumlordFight extends ScriptableSystem {
  private persistent let m_stage: Int32;       // 0 waiting, 1 texts arriving, 2 quest active, 3 won
  private persistent let m_textsSent: Int32;
  private persistent let m_thanked: Bool;      // Karl's thank-you text after the win
  private persistent let m_started: Bool;      // quest shown since Oshima's call ("Buy up Watson (n/5)")

  private let m_ticking: Bool;
  private let m_textQueued: Bool;
  private let m_textGateWaits: Int32;           // text retries spent waiting on the quest gate alone (not saved)
  private let m_skipTextGate: Bool;             // Debug_StartTexts: texts skip the quest gate
  private let m_pinId: NewMappinID;
  private let m_pinOn: Bool;

  private let m_lastScene: Int32;
  private let m_lastFight: Int32;
  private let m_lastFled: Int32;
  private let m_fightTicks: Int32;
  private let m_dodgeSide: Float;
  private let m_oshima: EntityID;              // the community's Oshima, seen attaching near the door
  private let m_seen: array<EntityID>;         // NPCs that attached near the door (Entity/Attach)
  private let m_clearIds: array<EntityID>;     // vanilla NPCs at the door we destroyed

  public static func GetInstance(game: GameInstance) -> ref<SlumlordFight> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordFight") as SlumlordFight;
  }

  public static func Property() -> CName { return n"wat_harbor_safehouse"; }
  public static func ClearRadius() -> Float { return 30.0; }      // vanilla gang NPCs this close to the door are removed
  public static func SeenRadius() -> Float { return 120.0; }
  public static func TextGapSeconds() -> Float { return 8.0; }
  public static func DoneFact() -> String { return "slumlord_wat_boss_done"; }
  public static func RewardXP() -> Int32 { return 1000; }
  public static func ThanksDelay() -> Float { return 20.0; }
  public static func OshimaRecord() -> TweakDBID { return t"Character.q005_hideyoshi_oshima"; }

  // The records the quest's communities spawn (tools/quest/make_scenes.py): never cleared away.
  public static func IsSceneRecord(id: TweakDBID) -> Bool {
    let ours: array<TweakDBID> = [t"Character.slumlord_fc_knocker", t"Character.slumlord_fc_welder",
                                  t"Character.slumlord_fc_smoker", t"Character.slumlord_fc_talker",
                                  SlumlordFight.OshimaRecord()];
    return ArrayContains(ours, id);
  }

  private func Fact(name: CName) -> Int32 {
    return GameInstance.GetQuestsSystem(this.GetGameInstance()).GetFact(name);
  }

  private func SetFact(name: CName, value: Int32) -> Void {
    let quests = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if quests.GetFact(name) != value { quests.SetFact(name, value); }
  }

  private func OnAttach() -> Void {
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attach", this, n"OnEntityAttach").AddTarget(EntityTarget.Type(n"NPCPuppet"));
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Detach", this, n"OnEntityDetach").AddTarget(EntityTarget.Type(n"NPCPuppet"));
  }

  private func OnDetach() -> Void {
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attach", this, n"OnEntityAttach");
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Detach", this, n"OnEntityDetach");
  }

  private cb func OnEntityAttach(event: ref<EntityLifecycleEvent>) {
    let npc = event.GetEntity() as NPCPuppet;
    if !IsDefined(npc) { return; }
    if Vector4.Distance(npc.GetWorldPosition(), SlumlordPositions.Get(SlumlordFight.Property())) > SlumlordFight.SeenRadius() { return; }
    if npc.GetRecordID() == SlumlordFight.OshimaRecord() { this.m_oshima = npc.GetEntityID(); }
    if !ArrayContains(this.m_seen, npc.GetEntityID()) { ArrayPush(this.m_seen, npc.GetEntityID()); }
  }

  private cb func OnEntityDetach(event: ref<EntityLifecycleEvent>) {
    let entity = event.GetEntity();
    if IsDefined(entity) { ArrayRemove(this.m_seen, entity.GetEntityID()); }
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_ticking = false;
    this.m_textQueued = false;
    this.m_pinOn = false;
    this.m_lastScene = -1;
    this.m_lastFight = -1;
    this.m_lastFled = -1;
    // Saves from before the quest started at the call: show it now.
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    if this.m_stage == 0 && !this.m_started && IsDefined(boss) && boss.IsCallDone() {
      this.StartQuest(false);
    }
    if this.m_stage == 3 {
      this.UnlockOshima();
    }
    this.SetFact(n"slumlord_fc_ready", this.m_stage == 2 ? 1 : 0);
    if this.m_stage == 3 && !this.m_thanked {
      this.Queue(n"thanks", 10.0);
    } else if this.m_stage == 1 {
      this.QueueText(5.0);
    } else if this.m_stage == 2 {
      this.StartQuestLoop();
    } else {
      this.Queue(n"check", 10.0);
    }
  }

  // ---- the quest starts when Oshima's call ends: "Buy up Watson (n/5)" ----

  public func OnCallDone() -> Void {
    if this.m_stage == 0 && !this.m_started {
      this.StartQuest(true);
    }
    this.CheckTrigger();
  }

  private func StartQuest(notify: Bool) -> Void {
    let game = this.GetGameInstance();
    if !SlumlordJournal.Installed(game) { return; }
    this.m_started = true;
    SlumlordJournal.Set(game, SlumlordJournal.Quest(), "gameJournalQuest", gameJournalEntryState.Active, notify);
    SlumlordJournal.Set(game, SlumlordJournal.Quest() + "/slumlord_fc_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordJournal.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Active, false);
    SlumlordBuyUp.Update(game, SlumlordJournal.Phase(), "slumlord_fc_buy_", n"watson", true);
    SlumlordUi.Log("Million Dollar Baby: started after Oshima's call");
  }

  // Every purchase and release (System.reds).
  public func OnPropertyChanged() -> Void {
    if this.m_started && this.m_stage == 0 {
      SlumlordBuyUp.Update(this.GetGameInstance(), SlumlordJournal.Phase(), "slumlord_fc_buy_", n"watson", false);
    }
    this.CheckTrigger();
  }

  private func UnlockOshima() -> Void {
    let sys = SlumlordSystem.GetInstance(this.GetGameInstance());
    if IsDefined(sys) {
      sys.UnlockContractor(n"con_oshima");
    }
  }

  // ---- trigger: all five Watson properties owned, Oshima's call done ----

  // Called on every purchase, at the end of Oshima's call and after loading a save.
  public func CheckTrigger() -> Void {
    if this.m_stage != 0 { return; }
    let game = this.GetGameInstance();
    if !SlumlordFight.WatsonComplete(game) { return; }
    let boss = SlumlordBoss.GetInstance(game);
    if !IsDefined(boss) || !boss.IsCallDone() {
      SlumlordUi.Log("Million Dollar Baby: Watson owned, waiting for Oshima's call to finish first");
      return;
    }
    this.BeginTexts(30.0);
  }

  public static func WatsonOwned(game: GameInstance, out total: Int32) -> Int32 {
    let owned = 0;
    total = 0;
    let sys = SlumlordSystem.GetInstance(game);
    if !IsDefined(sys) { return 0; }
    for def in sys.GetProperties() {
      if Equals(def.districtId, n"watson") {
        total += 1;
        let state = sys.GetState(def.id);
        if IsDefined(state) && state.owned { owned += 1; }
      }
    }
    return owned;
  }

  public static func WatsonComplete(game: GameInstance) -> Bool {
    let total: Int32;
    let owned = SlumlordFight.WatsonOwned(game, total);
    return total > 0 && owned == total;
  }

  private func BeginTexts(delay: Float) -> Void {
    if !SlumlordJournal.Installed(this.GetGameInstance()) {
      SlumlordUi.Log("Million Dollar Baby: journal missing (Slumlord.archive / Slumlord.archive.xl not installed)");
      return;
    }
    this.m_stage = 1;
    this.m_textsSent = 0;
    if this.m_started {
      SlumlordBuyUp.Update(this.GetGameInstance(), SlumlordJournal.Phase(), "slumlord_fc_buy_", n"watson", false);   // 5/5 done
    }
    SlumlordUi.Log("Million Dollar Baby: Watson owned, Karl texts in " + FloatToStringPrec(delay, 0) + " s");
    this.QueueText(delay);
  }

  // ---- Karl's texts ----

  private func QueueText(seconds: Float) -> Void {
    if this.m_textQueued { return; }
    this.m_textQueued = true;
    this.Queue(n"text", seconds);
  }

  private func SendNextText() -> Void {
    this.m_textQueued = false;
    if this.m_stage != 1 { return; }
    let game = this.GetGameInstance();
    // A scene, combat, a call or the main story: Karl texts a little later (10 minutes at most, so a stuck gate
    // can't hold the quest back; the debug start skips the wait).
    if !this.m_skipTextGate && !SlumlordGameFree.Now(game) && this.m_textGateWaits < 40 {
      this.m_textGateWaits += 1;
      this.QueueText(15.0);
      return;
    }
    this.m_textGateWaits = 0;
    if this.m_textsSent == 0 {
      SlumlordJournal.Set(game, SlumlordJournal.Karl(), "gameJournalContact", gameJournalEntryState.Active, false);
      SlumlordJournal.Set(game, SlumlordJournal.Thread(), "gameJournalPhoneConversation", gameJournalEntryState.Active, false);
    }
    this.m_textsSent += 1;
    SlumlordJournal.Set(game, SlumlordJournal.Thread() + "/slumlord_karl_0" + IntToString(this.m_textsSent),
                        "gameJournalPhoneMessage", gameJournalEntryState.Active, true);
    if this.m_textsSent < 5 {
      this.QueueText(SlumlordFight.TextGapSeconds());
      return;
    }
    // last text: the quest
    this.m_skipTextGate = false;
    this.m_stage = 2;
    this.SetFact(n"slumlord_fc_won", 0);   // a win fact left from an earlier run must not count
    SlumlordJournal.Set(game, SlumlordJournal.Quest(), "gameJournalQuest", gameJournalEntryState.Active, true);
    SlumlordJournal.Set(game, SlumlordJournal.Quest() + "/slumlord_fc_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordJournal.Quest() + "/slumlord_fc_desc", "gameJournalQuestDescription", gameJournalEntryState.Active, false);
    SlumlordJournal.Set(game, SlumlordJournal.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Active, false);
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Active);
    SlumlordJournal.Set(game, SlumlordJournal.Phase() + "/slumlord_fc_go/slumlord_fc_pin", "gameJournalQuestMapPin", gameJournalEntryState.Active, false);
    SlumlordJournal.Track(game, "slumlord_fc_go");
    this.StartQuestLoop();
  }

  // ---- the quest loop: once a second while the quest is active ----

  private func StartQuestLoop() -> Void {
    this.SetPin(false);
    this.SetFact(n"slumlord_fc_ready", 1);
    if this.Fact(n"slumlord_fc_fight") == 0 {
      SlumlordJournal.Set(this.GetGameInstance(), SlumlordJournal.Phase() + "/slumlord_fc_go/slumlord_fc_pin", "gameJournalQuestMapPin", gameJournalEntryState.Active, false);
    }
    SlumlordUi.Log("Million Dollar Baby: pin " + SlumlordFight.JournalPinState(this.GetGameInstance()));
    this.Queue(n"pincheck", 5.0);
    if !this.m_ticking {
      this.m_ticking = true;
      this.Queue(n"tick", 1.0);
    }
  }

  private func Tick() -> Void {
    this.m_ticking = false;
    if this.m_stage != 2 { return; }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    this.SetFact(n"slumlord_fc_ready", 1);
    let scene = this.Fact(n"slumlord_fc_scene");
    let fight = this.Fact(n"slumlord_fc_fight");
    let fled = this.Fact(n"slumlord_fc_fled");
    if IsDefined(player) {
      if scene == 1 && fight == 0 { this.ClearLocals(player); }
      if scene == 1 && this.m_lastScene != 1 {
        SlumlordUi.Log("Million Dollar Baby: encounter up (quest phase)");
      }
      if fight != this.m_lastFight && fight == 1 { this.OnFightStarts(); }
      if fight == 1 && fled == 0 {
        this.m_fightTicks += 1;
        if this.m_fightTicks % 3 == 1 { this.Dodge(player); }
      }
      if fled == 1 && this.m_lastFled == 0 { this.OshimaRuns(player); }
      if scene == 0 && this.m_lastScene == 1 && this.Fact(n"slumlord_fc_won") == 0 { this.OnEncounterEnded(); }
    }
    this.m_lastScene = scene;
    this.m_lastFight = fight;
    this.m_lastFled = fled;
    if this.Fact(n"slumlord_fc_won") == 1 {
      this.Win();
      return;
    }
    if this.m_stage == 2 {
      this.m_ticking = true;
      this.Queue(n"tick", 1.0);
    }
  }

  private func OnFightStarts() -> Void {
    let game = this.GetGameInstance();
    this.m_fightTicks = 0;
    this.m_dodgeSide = 1.0;
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Succeeded);
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Active);
    SlumlordJournal.Track(game, "slumlord_fc_fight");
    SlumlordUi.Log("Million Dollar Baby: fight on");
  }

  // V walked away mid-encounter: the quest phase despawned everyone and waits again.
  private func OnEncounterEnded() -> Void {
    let game = this.GetGameInstance();
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Inactive);
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Active);
    SlumlordJournal.Set(game, SlumlordJournal.Phase() + "/slumlord_fc_go/slumlord_fc_pin", "gameJournalQuestMapPin", gameJournalEntryState.Active, false);
    SlumlordJournal.Track(game, "slumlord_fc_go");
    SlumlordUi.Log("Million Dollar Baby: V left, encounter reset");
  }

  // ---- Oshima: Sandevistan dashes, then the sprint away ----

  private func Oshima() -> ref<NPCPuppet> {
    let npc = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_oshima) as NPCPuppet;
    if IsDefined(npc) && npc.GetRecordID() == SlumlordFight.OshimaRecord() { return npc; }
    for id in this.m_seen {
      npc = GameInstance.FindEntityByID(this.GetGameInstance(), id) as NPCPuppet;
      if IsDefined(npc) && npc.GetRecordID() == SlumlordFight.OshimaRecord() {
        this.m_oshima = id;
        return npc;
      }
    }
    return null;
  }

  // One Sandevistan dash, 4 m across V's line of fire, kept within 7 m of the door.
  private func Dodge(player: ref<PlayerPuppet>) -> Void {
    let oshima = this.Oshima();
    if !IsDefined(oshima) { return; }
    let toV = player.GetWorldPosition() - oshima.GetWorldPosition();
    toV.Z = 0.0;
    toV = Vector4.Normalize(toV);
    let across = new Vector4(toV.Y, -toV.X, 0.0, 0.0);
    let target = oshima.GetWorldPosition() + across * (4.0 * this.m_dodgeSide);
    let door = SlumlordPositions.Get(SlumlordFight.Property());
    let fromDoor = target - door;
    fromDoor.Z = 0.0;
    if Vector4.Length(fromDoor) > 7.0 {
      target = oshima.GetWorldPosition() - across * (4.0 * this.m_dodgeSide);
    }
    GameObjectEffectHelper.StartEffectEvent(oshima, this.m_dodgeSide > 0.0 ? n"fx_sandevistan_right" : n"fx_sandevistan_left");
    TimeDilationHelper.SetIndividualTimeDilation(oshima, n"slumlordSandevistan", 4.0, 0.7, n"SandevistanEaseIn", n"SandevistanEaseOut");
    this.MoveTo(oshima, target, 0.5);
    this.m_dodgeSide = -this.m_dodgeSide;
  }

  private func MoveTo(npc: ref<NPCPuppet>, target: Vector4, within: Float, opt type: moveMovementType, opt face: ref<GameObject>) -> Void {
    let world: WorldPosition;
    WorldPosition.SetVector4(world, target);
    let command = new AIMoveToCommand();
    AIPositionSpec.SetWorldPosition(command.movementTarget, world);
    command.movementType = Equals(type, moveMovementType.Walk) ? moveMovementType.Walk : moveMovementType.Sprint;
    if IsDefined(face) {
      AIPositionSpec.SetEntity(command.facingTarget, face);
      command.rotateEntityTowardsFacingTarget = true;
    }
    command.desiredDistanceFromTarget = within;
    command.finishWhenDestinationReached = true;
    command.ignoreInCombat = false;
    let ai = npc.GetAIControllerComponent();
    if IsDefined(ai) {
      ai.SendCommand(command);
    }
  }

  // He has shouted (the quest's flee scene): sprint 60 m away from V under time dilation; the quest despawns
  // him 8 s later.
  private func OshimaRuns(player: ref<PlayerPuppet>) -> Void {
    let oshima = this.Oshima();
    if !IsDefined(oshima) { return; }
    let away = oshima.GetWorldPosition() - player.GetWorldPosition();
    away.Z = 0.0;
    let target = oshima.GetWorldPosition() + Vector4.Normalize(away) * 60.0;
    TimeDilationHelper.SetIndividualTimeDilation(oshima, n"slumlordSandevistan", 2.5, 6.0, n"SandevistanEaseIn", n"SandevistanEaseOut");
    this.MoveTo(oshima, target, 2.0);
    SlumlordUi.Log("Million Dollar Baby: Oshima runs");
  }

  private func Win() -> Void {
    let game = this.GetGameInstance();
    this.m_stage = 3;
    this.SetFact(n"slumlord_fc_ready", 0);
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Succeeded);
    SlumlordJournal.Set(game, SlumlordJournal.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordJournal.Quest(), "gameJournalQuest", gameJournalEntryState.Succeeded, true);
    this.SetPin(false);
    GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordFight.DoneFact(), 1);
    this.UnlockOshima();   // he joins V as Contractor #16 (design doc 4.4)
    RPGManager.AwardExperienceInstantly(GetPlayer(game), SlumlordFight.RewardXP(), gamedataProficiencyType.Level);
    this.Queue(n"thanks", SlumlordFight.ThanksDelay());
    SlumlordUi.Log("Million Dollar Baby: won, Watson dominated");
  }

  private func SendThanks() -> Void {
    if this.m_stage != 3 || this.m_thanked { return; }
    this.m_thanked = true;
    SlumlordJournal.Set(this.GetGameInstance(), SlumlordJournal.Thread() + "/slumlord_karl_06", "gameJournalPhoneMessage", gameJournalEntryState.Active, true);
    SlumlordUi.Log("Million Dollar Baby: Karl says thanks");
  }

  // ---- the gang already hanging out at the Safehouse ----
  // A vanilla group of Maelstromers idles at the door (they sit in workspots). The game refuses a despawn request
  // for them and teleporting does not move them (2026-11-18 log), so their entities are destroyed outright, every
  // tick from the moment the quest phase starts the encounter until the fight (the phase waits 2 s before it
  // spawns its own people). Never the scene's records.

  private func ClearLocals(player: ref<PlayerPuppet>) -> Void {
    let game = this.GetGameInstance();
    let door = SlumlordPositions.Get(SlumlordFight.Property());
    let i = ArraySize(this.m_seen) - 1;
    while i >= 0 {
      let seen = GameInstance.FindEntityByID(game, this.m_seen[i]) as NPCPuppet;
      if !IsDefined(seen) {
        ArrayErase(this.m_seen, i);
      } else {
        this.MaybeRemove(seen, door);
      }
      i -= 1;
    }
    let query = TSQ_NPC();
    query.testedSet = TargetingSet.Complete;
    query.maxDistance = 180.0;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(game).GetTargetParts(player, query, parts);
    let done: array<EntityID>;    // each NPC has several target parts
    for part in parts {
      let comp = TS_TargetPartInfo.GetComponent(part);
      let npc = IsDefined(comp) ? comp.GetEntity() as NPCPuppet : null;
      if IsDefined(npc) && !ArrayContains(done, npc.GetEntityID()) {
        ArrayPush(done, npc.GetEntityID());
        this.MaybeRemove(npc, door);
      }
    }
  }

  private func MaybeRemove(npc: ref<NPCPuppet>, door: Vector4) -> Void {
    if npc.IsDead() || SlumlordFight.IsSceneRecord(npc.GetRecordID()) { return; }
    if Vector4.Distance(npc.GetWorldPosition(), door) >= SlumlordFight.ClearRadius() || !SlumlordFight.IsMaelstrom(npc) { return; }
    this.RemoveLocal(npc);
  }

  // Affiliation, live attitude group and record's base group, e.g. "Maelstrom/maelstrom/maelstrom".
  // Open-world NPCs can carry variant groups (Cerberus Ride uses "militech_ow"), so match by substring.
  public static func GangInfo(npc: ref<NPCPuppet>) -> String {
    let affiliation = "";
    let baseGroup = "";
    let record = TweakDBInterface.GetCharacterRecord(npc.GetRecordID());
    if IsDefined(record) {
      if IsDefined(record.Affiliation()) { affiliation = NameToString(record.Affiliation().EnumName()); }
      baseGroup = NameToString(record.BaseAttitudeGroup());
    }
    let agent = npc.GetAttitudeAgent();
    let group = IsDefined(agent) ? NameToString(agent.GetAttitudeGroup()) : "";
    return affiliation + "/" + group + "/" + baseGroup;
  }

  public static func IsMaelstrom(npc: ref<NPCPuppet>) -> Bool {
    return StrContains(StrLower(SlumlordFight.GangInfo(npc)), "maelstrom");
  }

  // Every NPC near the door, for the CET readout (the scene's own marked "ours").
  public func DescribeLocals() -> String {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) { return ""; }
    let door = SlumlordPositions.Get(SlumlordFight.Property());
    let query = TSQ_NPC();
    query.testedSet = TargetingSet.Complete;
    query.maxDistance = 250.0;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(this.GetGameInstance()).GetTargetParts(player, query, parts);
    let done: array<EntityID>;
    let out = "";
    for part in parts {
      let comp = TS_TargetPartInfo.GetComponent(part);
      let npc = IsDefined(comp) ? comp.GetEntity() as NPCPuppet : null;
      if IsDefined(npc) && !ArrayContains(done, npc.GetEntityID()) {
        ArrayPush(done, npc.GetEntityID());
        let d = Vector4.Distance(npc.GetWorldPosition(), door);
        if d < 45.0 {
          out += " [" + FloatToStringPrec(d, 0) + "m " + (SlumlordFight.IsSceneRecord(npc.GetRecordID()) ? "ours " : "")
            + SlumlordFight.GangInfo(npc) + (npc.IsDead() ? " dead" : "") + "]";
        }
      }
    }
    return Equals(out, "") ? " none" : out;
  }

  private func RemoveLocal(npc: ref<NPCPuppet>) -> Void {
    let id = npc.GetEntityID();
    if !ArrayContains(this.m_clearIds, id) {
      ArrayPush(this.m_clearIds, id);
      SlumlordUi.Log("Million Dollar Baby: removing a vanilla Maelstromer at the door (" + TDBID.ToStringDEBUG(npc.GetRecordID()) + ")");
    }
    EntityGameInterface.Destroy(npc.GetEntity());
  }

  // ---- quest pin at the Safehouse ----
  // The pin is a journal map pin (slumlord_fc_pin under the "go" objective) on a world anchor: the marker node
  // $/slumlord/final_cut/#slumlord_fc_marker in slumlord_markers.streamingsector (AlwaysLoaded), so the game
  // draws it and routes GPS to it while the objective is tracked. Script-registered pins did not render.
  // SetPin only clears a script pin left by an older build.

  private func SetPin(on: Bool) -> Void {
    if this.m_pinOn {
      GameInstance.GetMappinSystem(this.GetGameInstance()).UnregisterMappin(this.m_pinId);
      this.m_pinOn = false;
    }
  }

  public static func JournalPinState(game: GameInstance) -> String {
    let jm = GameInstance.GetJournalManager(game);
    let pin = jm.GetEntryByString(SlumlordJournal.Phase() + "/slumlord_fc_go/slumlord_fc_pin", "gameJournalQuestMapPin");
    if !IsDefined(pin) { return "missing from journal"; }
    let phase = jm.GetEntryByString(SlumlordJournal.Phase(), "gameJournalQuestPhase");
    let obj = jm.GetEntryByString(SlumlordJournal.Phase() + "/slumlord_fc_go", "gameJournalQuestObjective");
    let marker = GameInstance.GetMappinSystem(game).GetMappinFromObjective(phase, obj);
    return "in journal, map marker " + (IsDefined(marker) ? "yes" : "no");
  }

  // ---- callbacks and debug ----

  private func Queue(action: CName, seconds: Float) -> Void {
    let cb = new SlumlordFightCallback();
    cb.system = this;
    cb.action = action;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, seconds, false);
  }

  public func OnCallback(action: CName) -> Void {
    if Equals(action, n"text") {
      this.SendNextText();
    } else if Equals(action, n"tick") {
      this.Tick();
    } else if Equals(action, n"check") {
      this.CheckTrigger();
    } else if Equals(action, n"thanks") {
      this.SendThanks();
    } else if Equals(action, n"pincheck") {
      SlumlordUi.Log("Million Dollar Baby: pin after 5 s: " + SlumlordFight.JournalPinState(this.GetGameInstance()));
    }
  }

  // Ends a running encounter (the quest phase despawns everyone and waits again).
  private func AbortEncounter() -> Void {
    if this.Fact(n"slumlord_fc_scene") == 1 { this.SetFact(n"slumlord_fc_abort", 1); }
    this.SetFact(n"slumlord_fc_tries", 0);
  }

  public func Debug_StartTexts() -> Void {
    this.m_skipTextGate = true;
    this.m_textGateWaits = 0;
    this.AbortEncounter();
    this.m_stage = 0;
    this.SetFact(n"slumlord_fc_ready", 0);
    this.SetFact(n"slumlord_fc_won", 0);
    GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFactStr(SlumlordFight.DoneFact(), 0);
    this.BeginTexts(2.0);
  }

  // Ends the running Safehouse encounter (the quest phase cleans up) and clears the spawn-retry count; the quest
  // stays at its stage, so the phase starts the encounter again about 5 s later while V is in range.
  public func Debug_RestartEncounter() -> Void {
    this.AbortEncounter();
  }

  public func Debug_Reset() -> Void {
    let game = this.GetGameInstance();
    this.AbortEncounter();
    this.m_skipTextGate = false;
    this.m_textGateWaits = 0;
    this.SetPin(false);
    this.m_stage = 0;
    this.m_textsSent = 0;
    this.m_started = false;
    this.SetFact(n"slumlord_fc_ready", 0);
    this.SetFact(n"slumlord_fc_won", 0);
    SlumlordBuyUp.Clear(game, SlumlordJournal.Phase(), "slumlord_fc_buy_");
    SlumlordJournal.Set(game, SlumlordJournal.Quest() + "/slumlord_fc_desc_intro", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Inactive);
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Inactive);
    SlumlordJournal.Set(game, SlumlordJournal.Phase() + "/slumlord_fc_go/slumlord_fc_pin", "gameJournalQuestMapPin", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordJournal.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordJournal.Quest() + "/slumlord_fc_desc", "gameJournalQuestDescription", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordJournal.Quest(), "gameJournalQuest", gameJournalEntryState.Inactive, false);
    this.m_thanked = false;
    let i = 1;
    while i <= 6 {
      SlumlordJournal.Set(game, SlumlordJournal.Thread() + "/slumlord_karl_0" + IntToString(i), "gameJournalPhoneMessage", gameJournalEntryState.Inactive, false);
      i += 1;
    }
    SlumlordJournal.Set(game, SlumlordJournal.Thread(), "gameJournalPhoneConversation", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordJournal.Karl(), "gameJournalContact", gameJournalEntryState.Inactive, false);
    GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordFight.DoneFact(), 0);
  }

  public func Debug_State() -> String {
    let total: Int32;
    let owned = SlumlordFight.WatsonOwned(this.GetGameInstance(), total);
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    return "watson " + IntToString(owned) + "/" + IntToString(total) + " call=" + (IsDefined(boss) && boss.IsCallDone() ? "done" : "not done")
      + " started=" + (this.m_started ? "yes" : "no") + " stage=" + IntToString(this.m_stage) + " texts=" + IntToString(this.m_textsSent)
      + " | quest phase: ready=" + IntToString(this.Fact(n"slumlord_fc_ready")) + " scene=" + IntToString(this.Fact(n"slumlord_fc_scene"))
      + " fight=" + IntToString(this.Fact(n"slumlord_fc_fight")) + " fled=" + IntToString(this.Fact(n"slumlord_fc_fled"))
      + " won=" + IntToString(this.Fact(n"slumlord_fc_won")) + " abort=" + IntToString(this.Fact(n"slumlord_fc_abort"))
      + " tries=" + IntToString(this.Fact(n"slumlord_fc_tries"))
      + " game free=" + (this.Fact(n"slumlord_gate_on") == 1 ? IntToString(this.Fact(n"slumlord_game_free")) : "no gate")
      + " Oshima=" + (IsDefined(this.Oshima()) ? "found" : "not seen") + " cleared=" + IntToString(ArraySize(this.m_clearIds))
      + " | pin=" + SlumlordFight.JournalPinState(this.GetGameInstance())
      + " near door:" + this.DescribeLocals()
      + " journal=" + (SlumlordJournal.Installed(this.GetGameInstance()) ? "yes" : "no");
  }
}

public class SlumlordFightCallback extends DelayCallback {
  public let system: wref<SlumlordFight>;
  public let action: CName;

  public func Call() -> Void {
    let sys = this.system;
    if IsDefined(sys) {
      sys.OnCallback(this.action);
    }
  }
}
