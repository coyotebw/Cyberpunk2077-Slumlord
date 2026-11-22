// Conversation Overtime's motel scene (design doc 4.9 and 13), at Las Palapas, at night, once V owns all of
// Santo Domingo. Since 2026-11-22 the scene is the game's own quest files (tools/quest/make_motel.py):
// slumlord\quest\slumlord_motel.questphase spawns Finger and three 6th Street goons from communities on AI spots,
// clears the crowd (a crowd null area), plays the standoff scene, turns the goons hostile, waits until they are
// down, plays the truce scene and walks Finger off. This system is the bridge to it, through quest facts:
//
//   slumlord_co_ready      set here: 1 while V should meet Finger now (stage 3, night) -> the phase may start
//   slumlord_co_scene      read here: 1 while the encounter is up -> spawn the bike, clear bystanders
//   slumlord_co_fight      read here: 1 fighting, 2 goons down -> journal objectives
//   slumlord_co_motel_won  read here: 1 after the truce -> SlumlordFinger.Win()
//   slumlord_co_abort      set here: 1 ends the encounter (debug, or the quest is no longer at the motel stage)
//
// What stays in script: the bike that isn't V's (a vehicle prop), and removing vanilla NPCs that the crowd null
// area doesn't cover (community NPCs) near Finger's spot until the fight starts.
module Slumlord

public class SlumlordMotelScene extends ScriptableSystem {
  private let m_ticking: Bool;
  private let m_bike: EntityID;
  private let m_bikeUp: Bool;
  private let m_lastScene: Int32;
  private let m_lastFight: Int32;
  private let m_clearIds: array<EntityID>;
  private let m_seen: array<EntityID>;        // vanilla NPCs that attached near Las Palapas (Entity/Attach)
  private let m_anyTime: Bool;                // debug: by day too

  public static func GetInstance(game: GameInstance) -> ref<SlumlordMotelScene> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordMotelScene") as SlumlordMotelScene;
  }

  public static func BikeTag() -> CName { return n"SlumlordConversationOvertimeBike"; }
  public static func ClearRadius() -> Float { return 45.0; }
  public static func SeenRadius() -> Float { return 120.0; }
  public static func NearDistance() -> Float { return 350.0; }

  // Captured in game 2026-11-19 ("Capture spot", motel_bike). Yaw = facing, degrees.
  public static func BikePos() -> Vector4 { return new Vector4(-1083.34, -1525.00, 25.78, 1.0); }
  public static func BikeYaw() -> Float { return -42.8; }

  // The records the quest's communities spawn (tools/quest/make_motel.py): never cleared away.
  public static func FingerRecord() -> TweakDBID { return t"Character.slumlord_quentin_finger"; }
  public static func IsSceneRecord(id: TweakDBID) -> Bool {
    if id == SlumlordMotelScene.FingerRecord() { return true; }
    for r in SlumlordConversationOvertime.Goons() {
      if id == r { return true; }
    }
    return false;
  }

  private func Fact(name: CName) -> Int32 {
    return GameInstance.GetQuestsSystem(this.GetGameInstance()).GetFact(name);
  }

  private func SetFact(name: CName, value: Int32) -> Void {
    let quests = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if quests.GetFact(name) != value { quests.SetFact(name, value); }
  }

  // The fight is on (or over): Finger's journal objectives are the scene's until the win.
  public func IsBusy() -> Bool { return this.Fact(n"slumlord_co_scene") == 1 && this.Fact(n"slumlord_co_fight") >= 1; }

  private func OnAttach() -> Void {
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attach", this, n"OnEntityAttach").AddTarget(EntityTarget.Type(n"NPCPuppet"));
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Detach", this, n"OnEntityDetach").AddTarget(EntityTarget.Type(n"NPCPuppet"));
  }

  private func OnDetach() -> Void {
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attach", this, n"OnEntityAttach");
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Detach", this, n"OnEntityDetach");
  }

  // Every NPC that streams in near the motel is noted; while the encounter is up and before the fight, one that
  // appears inside the clear radius is removed at once (the targeting query only sees NPCs V could target).
  private cb func OnEntityAttach(event: ref<EntityLifecycleEvent>) {
    let npc = event.GetEntity() as NPCPuppet;
    if !IsDefined(npc) { return; }
    if Vector4.Distance(npc.GetWorldPosition(), SlumlordConversationOvertime.FingerSpot()) > SlumlordMotelScene.SeenRadius() { return; }
    if !ArrayContains(this.m_seen, npc.GetEntityID()) { ArrayPush(this.m_seen, npc.GetEntityID()); }
    if this.Clearing() { this.Queue(n"clear", 0.1); }   // let it finish attaching, then remove
  }

  private cb func OnEntityDetach(event: ref<EntityLifecycleEvent>) {
    let entity = event.GetEntity();
    if IsDefined(entity) { ArrayRemove(this.m_seen, entity.GetEntityID()); }
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_ticking = false;
    this.m_bikeUp = false;
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.BikeTag());
    this.m_lastScene = -1;
    this.m_lastFight = -1;
    this.Queue(n"tick", 5.0);
  }

  private func Clearing() -> Bool {
    return this.Fact(n"slumlord_co_scene") == 1 && this.Fact(n"slumlord_co_fight") == 0;
  }

  // ---- the loop ----

  private func Tick() -> Void {
    let game = this.GetGameInstance();
    let finger = SlumlordFinger.GetInstance(game);
    let player = GetPlayer(game);
    let wait = 5.0;
    if IsDefined(finger) && IsDefined(player) {
      let stage3 = finger.GetStage() == 3;
      let dist = Vector4.Distance(player.GetWorldPosition(), SlumlordConversationOvertime.FingerSpot());
      this.SetFact(n"slumlord_co_ready", stage3 && (finger.IsNightNow() || this.m_anyTime) ? 1 : 0);
      let scene = this.Fact(n"slumlord_co_scene");
      let fight = this.Fact(n"slumlord_co_fight");
      let won = this.Fact(n"slumlord_co_motel_won");
      if scene == 1 && !stage3 && won == 0 { this.SetFact(n"slumlord_co_abort", 1); }
      if scene == 1 {
        if !this.m_bikeUp { this.SpawnBike(); }
        if fight == 0 { this.ClearLocals(player); }
      } else if this.m_bikeUp && this.m_lastScene == 1 && won == 0 {
        GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.BikeTag());
        this.m_bikeUp = false;
        if stage3 { finger.RefreshObjectives(); }
        SlumlordUi.Log("Conversation Overtime: motel encounter ended before the win");
      }
      if fight != this.m_lastFight && stage3 { this.OnFight(fight); }
      if won == 1 && stage3 {
        finger.Win();
        SlumlordUi.Log("Conversation Overtime: truce scene done, won");
      }
      this.m_lastScene = scene;
      this.m_lastFight = fight;
      wait = dist < SlumlordMotelScene.NearDistance() ? 1.0 : 5.0;
    }
    this.Queue(n"tick", wait);
  }

  private func OnFight(fight: Int32) -> Void {
    let game = this.GetGameInstance();
    if fight == 1 {
      SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_wait", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
      SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_motel", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
      SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_goons", "gameJournalQuestObjective", gameJournalEntryState.Active, false);
      SlumlordBuyUp.Track(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_goons");
      SlumlordUi.Log("Conversation Overtime: fight on");
    } else if fight == 2 {
      SlumlordUi.Log("Conversation Overtime: goons down, Finger comes out");
    }
  }

  private func SpawnBike() -> Void {
    let des = GameInstance.GetDynamicEntitySystem();
    des.DeleteTagged(SlumlordMotelScene.BikeTag());
    let spec = new DynamicEntitySpec();
    spec.recordID = TDBID.Create(SlumlordConversationOvertime.BikeRecord());
    spec.position = SlumlordMotelScene.BikePos();
    let angles: EulerAngles;
    angles.Yaw = SlumlordMotelScene.BikeYaw();
    spec.orientation = EulerAngles.ToQuat(angles);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.spawnInView = true;
    spec.active = true;
    spec.tags = [SlumlordMotelScene.BikeTag()];
    this.m_bike = des.CreateEntity(spec);
    this.m_bikeUp = true;
    ArrayClear(this.m_clearIds);
    SlumlordUi.Log("Conversation Overtime: motel encounter up (quest phase), bike spawned");
  }

  // ---- clearing the area ----
  // Las Palapas is dense. The crowd null area takes care of the crowd; community NPCs are destroyed here (the game
  // refuses despawn requests for some, Fight.reds 2026-11-18), every second until the fight starts.

  private func ClearLocals(player: ref<PlayerPuppet>) -> Void {
    let center = SlumlordConversationOvertime.FingerSpot();
    let i = ArraySize(this.m_seen) - 1;
    while i >= 0 {
      let seen = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_seen[i]) as NPCPuppet;
      if !IsDefined(seen) {
        ArrayErase(this.m_seen, i);
      } else {
        this.MaybeRemove(seen, center);
      }
      i -= 1;
    }
    let query = TSQ_NPC();
    query.testedSet = TargetingSet.Complete;
    query.maxDistance = SlumlordMotelScene.SeenRadius() + 30.0;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(this.GetGameInstance()).GetTargetParts(player, query, parts);
    let done: array<EntityID>;
    for part in parts {
      let comp = TS_TargetPartInfo.GetComponent(part);
      let npc = IsDefined(comp) ? comp.GetEntity() as NPCPuppet : null;
      if IsDefined(npc) && !ArrayContains(done, npc.GetEntityID()) {
        ArrayPush(done, npc.GetEntityID());
        this.MaybeRemove(npc, center);
      }
    }
  }

  // Never the scene's own people; never anyone in combat, dead or hostile to V (destroying those left V stuck in
  // combat, 2026-11-21).
  private func MaybeRemove(npc: ref<NPCPuppet>, center: Vector4) -> Void {
    if SlumlordMotelScene.IsSceneRecord(npc.GetRecordID()) || npc.IsPlayerCompanion() { return; }
    if NPCPuppet.IsInCombat(npc) || npc.IsDead() { return; }
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(player) && Equals(GameObject.GetAttitudeBetween(npc, player), EAIAttitude.AIA_Hostile) { return; }
    if Vector4.Distance(npc.GetWorldPosition(), center) >= SlumlordMotelScene.ClearRadius() { return; }
    if !ArrayContains(this.m_clearIds, npc.GetEntityID()) { ArrayPush(this.m_clearIds, npc.GetEntityID()); }
    EntityGameInterface.Destroy(npc.GetEntity());
  }

  // ---- callbacks and debug ----

  private func Queue(action: CName, seconds: Float) -> Void {
    if Equals(action, n"tick") {
      if this.m_ticking { return; }
      this.m_ticking = true;
    }
    let cb = new SlumlordMotelCallback();
    cb.system = this;
    cb.action = action;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, seconds, false);
  }

  public func OnCallback(action: CName) -> Void {
    if Equals(action, n"tick") {
      this.m_ticking = false;
      this.Tick();
    } else if Equals(action, n"clear") {
      let player = GetPlayer(this.GetGameInstance());
      if IsDefined(player) && this.Clearing() { this.ClearLocals(player); }
    }
  }

  public func Debug_ToggleAnyTime() -> Bool {
    this.m_anyTime = !this.m_anyTime;
    this.Queue(n"tick", 0.1);
    return this.m_anyTime;
  }

  // Ends the encounter now: the quest phase despawns everyone and waits for V again.
  public func Debug_Clear() -> Void {
    this.SetFact(n"slumlord_co_abort", 1);
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.BikeTag());
    this.m_bikeUp = false;
  }

  // Facts back to their start (with Reset Conversation Overtime).
  public func Debug_ResetFacts() -> Void {
    this.SetFact(n"slumlord_co_motel_won", 0);
    this.SetFact(n"slumlord_co_abort", this.Fact(n"slumlord_co_scene") == 1 ? 1 : 0);
  }

  public func Debug_State() -> String {
    let player = GetPlayer(this.GetGameInstance());
    let dist = IsDefined(player) ? Vector4.Distance(player.GetWorldPosition(), SlumlordConversationOvertime.FingerSpot()) : -1.0;
    let finger = TweakDBInterface.GetCharacterRecord(SlumlordMotelScene.FingerRecord());
    return "motel (quest phase) ready=" + IntToString(this.Fact(n"slumlord_co_ready"))
      + " scene=" + IntToString(this.Fact(n"slumlord_co_scene"))
      + " fight=" + IntToString(this.Fact(n"slumlord_co_fight"))
      + " won=" + IntToString(this.Fact(n"slumlord_co_motel_won"))
      + " abort=" + IntToString(this.Fact(n"slumlord_co_abort"))
      + " any time=" + (this.m_anyTime ? "yes" : "no") + " dist=" + FloatToStringPrec(dist, 0) + "m"
      + " bike=" + (this.m_bikeUp ? "up" : "no") + " cleared NPCs=" + IntToString(ArraySize(this.m_clearIds))
      + " | Finger record " + (IsDefined(finger) ? "ok (TweakXL)" : "MISSING (TweakXL yaml not loaded)");
  }
}

public class SlumlordMotelCallback extends DelayCallback {
  public let system: wref<SlumlordMotelScene>;
  public let action: CName;

  public func Call() -> Void {
    let sys = this.system;
    if IsDefined(sys) { sys.OnCallback(this.action); }
  }
}
