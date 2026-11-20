// Conversation Overtime's motel scene (design doc 4.9), at Las Palapas, at night, once V owns all of Santo Domingo.
//
//  1 Waiting: V comes within 150 m at night (stage 3) -> Finger (arms crossed, at his spot), three 6th Street goons
//    (all at the one goon spot, a step apart) and a Yaiba Kusanagi that isn't V's are spawned. Every vanilla NPC
//    within 40 m of Finger's spot is removed, every second, until Finger walks off (the area is dense).
//  2 Standoff: V within 12 m of Finger -> SlumlordMotelScript.Standoff, ending with "Fuck it. Waste 'em!".
//    V opening fire or hurting a goon skips straight to the fight.
//  3 Fight: the goons turn hostile; Finger (invulnerable, never hostile) runs to his hiding place.
//  4 Truce: last goon down -> Finger comes out, walks up to V, SlumlordMotelScript.Truce.
//  5 Done: SlumlordFinger.Win() (garage bike, muscle owed, journal), Finger walks off and is removed.
// V walking 230 m away before the win clears the scene; it spawns again next time V comes back at night.
module Slumlord

public class SlumlordMotelScene extends ScriptableSystem {
  private let m_ticking: Bool;
  private let m_spawned: Bool;
  private let m_phase: Int32;                 // 0 none, 1 waiting, 2 standoff, 3 fight, 4 truce, 5 done
  private let m_finger: EntityID;
  private let m_goons: array<EntityID>;
  private let m_goonSeen: array<Bool>;        // configured at least once (spawns finish asynchronously)
  private let m_bike: EntityID;
  private let m_fingerReady: Bool;
  private let m_line: Int32;
  private let m_ticks: Int32;                 // seconds in the current phase
  private let m_lookAt: ref<LookAtAddEvent>;
  private let m_spotCommand: ref<AIUseWorkspotCommand>;
  private let m_clearIds: array<EntityID>;
  private let m_anyTime: Bool;                // debug: spawn by day too

  public static func GetInstance(game: GameInstance) -> ref<SlumlordMotelScene> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordMotelScene") as SlumlordMotelScene;
  }

  public static func Tag() -> CName { return n"SlumlordConversationOvertime"; }
  public static func BikeTag() -> CName { return n"SlumlordConversationOvertimeBike"; }
  public static func SpawnDistance() -> Float { return 150.0; }
  public static func TalkDistance() -> Float { return 12.0; }
  public static func ClearRadius() -> Float { return 40.0; }
  public static func LeaveDistance() -> Float { return 230.0; }
  public static func GoonSpacing() -> Float { return 1.3; }
  public static func FingerSpotRef() -> String { return "$/slumlord/conversation_overtime/#slumlord_co_spot_finger"; }

  // Captured in game 2026-11-19 ("Capture spot", motel_* names). Yaw = facing, degrees.
  public static func GoonPos() -> Vector4 { return new Vector4(-1074.25, -1527.08, 25.78, 1.0); }
  public static func GoonYaw() -> Float { return 1.4; }
  public static func BikePos() -> Vector4 { return new Vector4(-1083.34, -1525.00, 25.78, 1.0); }
  public static func BikeYaw() -> Float { return -42.8; }
  public static func HidePos() -> Vector4 { return new Vector4(-1098.00, -1537.78, 25.76, 1.0); }

  public func IsBusy() -> Bool { return this.m_phase >= 2 && this.m_phase <= 4; }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_spawned = false;
    this.m_phase = 0;
    this.m_ticking = false;
    this.DeleteScene();
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.BikeTag());
    this.Queue(n"tick", 5.0);
  }

  // ---- the loop ----

  private func Tick() -> Void {
    let game = this.GetGameInstance();
    let finger = SlumlordFinger.GetInstance(game);
    let player = GetPlayer(game);
    let wait = 1.0;
    if IsDefined(finger) && IsDefined(player) {
      let stage3 = finger.GetStage() == 3;
      let dist = Vector4.Distance(player.GetWorldPosition(), SlumlordConversationOvertime.FingerSpot());
      if !this.m_spawned {
        if stage3 && (finger.IsNightNow() || this.m_anyTime) && dist < SlumlordMotelScene.SpawnDistance() {
          this.Spawn();
        } else {
          wait = dist < SlumlordMotelScene.SpawnDistance() + 100.0 ? 1.0 : 5.0;
        }
      } else if this.m_phase < 5 && (!stage3 || dist > SlumlordMotelScene.LeaveDistance()) {
        this.Abandon(stage3 ? "V left" : "quest no longer at the motel stage");
      } else if this.m_phase == 5 {
        this.m_ticks += 1;
        if this.m_ticks == 12 || dist > SlumlordMotelScene.LeaveDistance() {
          this.DeleteScene();   // Finger has walked off; the bike stays
          this.m_spawned = false;
          this.m_phase = 0;
        }
      } else {
        this.m_ticks += 1;
        this.Configure(player);
        this.ClearLocals(player);
        if (this.m_phase == 1 || this.m_phase == 2) && (player.IsInCombat() || this.AnyGoonHurt()) {
          this.GoHostile();     // V opened fire first: skip the talk
        } else if this.m_phase == 1 && this.m_fingerReady && dist < SlumlordMotelScene.TalkDistance() {
          this.StartTalk();
        } else if this.m_phase == 3 {
          this.FightTick();
        }
      }
    }
    this.Queue(n"tick", wait);
  }

  // ---- spawning ----

  private func Spawn() -> Void {
    let des = GameInstance.GetDynamicEntitySystem();
    ArrayClear(this.m_goons);
    ArrayClear(this.m_goonSeen);
    ArrayClear(this.m_clearIds);
    // All three at the one goon spot, a step apart across the way they face.
    let across = SlumlordMotelScene.Across(SlumlordMotelScene.GoonYaw());
    let records = SlumlordMotelScene.GoonRecords();
    let i = 0;
    while i < ArraySize(records) {
      let offset = Cast<Float>(i - 1) * SlumlordMotelScene.GoonSpacing();
      ArrayPush(this.m_goons, this.SpawnRecord(records[i], SlumlordMotelScene.GoonPos() + across * offset, SlumlordMotelScene.GoonYaw(), SlumlordMotelScene.Tag()));
      ArrayPush(this.m_goonSeen, false);
      i += 1;
    }
    this.m_finger = this.SpawnRecord(SlumlordMotelScene.FingerRecord(), SlumlordConversationOvertime.FingerSpot(), SlumlordConversationOvertime.FingerSpotYaw(), SlumlordMotelScene.Tag());
    des.DeleteTagged(SlumlordMotelScene.BikeTag());
    this.m_bike = this.SpawnRecord(TDBID.Create(SlumlordConversationOvertime.BikeRecord()), SlumlordMotelScene.BikePos(), SlumlordMotelScene.BikeYaw(), SlumlordMotelScene.BikeTag());
    this.m_fingerReady = false;
    this.m_spotCommand = null;
    this.m_spawned = true;
    this.m_phase = 1;
    this.m_ticks = 0;
    this.m_line = 0;
    SlumlordUi.Log("Conversation Overtime: motel scene spawned (Finger " + TDBID.ToStringDEBUG(SlumlordMotelScene.FingerRecord()) + ", " + IntToString(ArraySize(this.m_goons)) + " goons, bike)");
  }

  // Finger's look is still to pick (an AMM/entSpawner record and appearance). Stand-in until then.
  public static func FingerRecord() -> TweakDBID {
    let wanted = t"Character.sixthstreet_prepers3_shotgun3_carnage_ma_rare";
    if IsDefined(TweakDBInterface.GetCharacterRecord(wanted)) { return wanted; }
    return t"Character.q005_hideyoshi_oshima";
  }

  // The 6th Street records that exist in this game version; Watson's Maelstromers if none do.
  public static func GoonRecords() -> array<TweakDBID> {
    let out: array<TweakDBID>;
    for r in SlumlordConversationOvertime.Goons() {
      if IsDefined(TweakDBInterface.GetCharacterRecord(r)) { ArrayPush(out, r); }
    }
    if ArraySize(out) == 0 {
      out = [t"Character.maelstrom_grunt1_ranged1_lexington_ma", t"Character.maelstrom_grunt1_ranged1_copperhead_ma", t"Character.maelstrom_grunt2_ranged2_ajax_wa"];
    }
    return out;
  }

  public static func RecordReport() -> String {
    let out = "Finger: " + TDBID.ToStringDEBUG(SlumlordMotelScene.FingerRecord()) + " | goons:";
    for r in SlumlordConversationOvertime.Goons() {
      out += " " + TDBID.ToStringDEBUG(r) + (IsDefined(TweakDBInterface.GetCharacterRecord(r)) ? " ok" : " MISSING");
    }
    let bike = TDBID.Create(SlumlordConversationOvertime.BikeRecord());
    out += " | bike " + SlumlordConversationOvertime.BikeRecord() + (IsDefined(TweakDBInterface.GetVehicleRecord(bike)) ? " ok" : " MISSING");
    return out;
  }

  private func SpawnRecord(record: TweakDBID, pos: Vector4, yaw: Float, tag: CName) -> EntityID {
    let spec = new DynamicEntitySpec();
    spec.recordID = record;
    spec.position = pos;
    let angles: EulerAngles;
    angles.Yaw = yaw;
    spec.orientation = EulerAngles.ToQuat(angles);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.spawnInView = true;
    spec.active = true;
    spec.tags = [tag];
    return GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
  }

  public static func Across(yaw: Float) -> Vector4 {
    let dir = SlumlordFight.YawDir(yaw);
    return new Vector4(dir.Y, -dir.X, 0.0, 0.0);
  }

  private func Npc(id: EntityID) -> ref<NPCPuppet> {
    return GameInstance.GetDynamicEntitySystem().GetEntity(id) as NPCPuppet;
  }

  // Keep everyone calm until the fight (6th Street is hostile to V on sight), Finger unkillable throughout.
  private func Configure(player: ref<PlayerPuppet>) -> Void {
    if this.m_phase <= 2 {
      let i = 0;
      while i < ArraySize(this.m_goons) {
        let npc = this.Npc(this.m_goons[i]);
        if IsDefined(npc) {
          if !this.m_goonSeen[i] {
            let agent = npc.GetAttitudeAgent();
            if IsDefined(agent) { agent.SetAttitudeGroup(n"neutral"); }
            this.m_goonSeen[i] = true;
          }
          this.Attitude(npc, player, EAIAttitude.AIA_Neutral);
        }
        i += 1;
      }
    }
    let finger = this.Npc(this.m_finger);
    if IsDefined(finger) {
      if !this.m_fingerReady {
        StatusEffectHelper.ApplyStatusEffect(finger, t"BaseStatusEffect.Invulnerable");
        let agent = finger.GetAttitudeAgent();
        if IsDefined(agent) { agent.SetAttitudeGroup(n"neutral"); }
        if this.m_phase == 1 { this.EnterSpot(finger); }
        this.m_fingerReady = true;
      }
      this.Attitude(finger, player, EAIAttitude.AIA_Neutral);
    }
  }

  private func EnterSpot(npc: ref<NPCPuppet>) -> Void {
    let ai = npc.GetAIControllerComponent();
    if !IsDefined(ai) { return; }
    let command = new AIUseWorkspotCommand();
    command.workspotNode = CreateNodeRef(SlumlordMotelScene.FingerSpotRef());
    command.moveToWorkspot = true;
    command.movementType = moveMovementType.Walk;
    command.continueInCombat = false;
    ai.SendCommand(command);
    this.m_spotCommand = command;
  }

  private func LeaveSpot(npc: ref<NPCPuppet>) -> Void {
    if !IsDefined(npc) { return; }
    let ai = npc.GetAIControllerComponent();
    if IsDefined(this.m_spotCommand) && IsDefined(ai) { ai.CancelCommand(this.m_spotCommand); }
    this.m_spotCommand = null;
    let workspots = GameInstance.GetWorkspotSystem(this.GetGameInstance());
    if workspots.IsActorInWorkspot(npc) { workspots.SendFastExitSignal(npc); }
  }

  private func Attitude(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>, attitude: EAIAttitude) -> Void {
    let agent = npc.GetAttitudeAgent();
    let pa = player.GetAttitudeAgent();
    if !IsDefined(agent) || !IsDefined(pa) { return; }
    agent.SetAttitudeTowards(pa, attitude);
    pa.SetAttitudeTowards(agent, attitude);
  }

  private func AnyGoonHurt() -> Bool {
    let pools = GameInstance.GetStatPoolsSystem(this.GetGameInstance());
    for id in this.m_goons {
      let npc = this.Npc(id);
      if IsDefined(npc) {
        if npc.IsDead() || pools.GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true) < 99.0 {
          return true;
        }
      }
    }
    return false;
  }

  // ---- talk ----

  private func StartTalk() -> Void {
    let game = this.GetGameInstance();
    this.m_phase = 2;
    this.m_ticks = 0;
    this.m_line = 0;
    SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_wait", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_motel", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
    let player = GetPlayer(game);
    let finger = this.Npc(this.m_finger);
    if IsDefined(player) && IsDefined(finger) {
      this.LookAtV(finger, player);
      this.LeaveSpot(finger);
      this.Queue(n"step", 1.0);   // after the exit animation
    }
    this.Queue(n"line", 0.5);
  }

  // A few steps toward V, stopping 4 m short.
  private func Approach() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    let finger = this.Npc(this.m_finger);
    if !IsDefined(player) || !IsDefined(finger) { return; }
    let toV = player.GetWorldPosition() - finger.GetWorldPosition();
    toV.Z = 0.0;
    let step = MinF(this.m_phase == 4 ? 30.0 : 2.5, MaxF(0.0, Vector4.Length(toV) - 4.0));
    this.MoveTo(finger, finger.GetWorldPosition() + Vector4.Normalize(toV) * step, 0.5, moveMovementType.Walk, player);
  }

  private func NextLine() -> Void {
    if this.m_phase != 2 && this.m_phase != 4 { return; }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let male = IsDefined(player) && Equals(player.GetResolvedGenderName(), n"Male");
    let line = new SlumlordCallLine();
    let more = this.m_phase == 2 ? SlumlordMotelScript.Standoff(this.m_line, male, line) : SlumlordMotelScript.Truce(this.m_line, male, line);
    if !more {
      if this.m_phase == 2 { this.GoHostile(); } else { this.Finish(); }
      return;
    }
    let isV = Equals(line.speaker, "V");
    let speaker: ref<GameObject> = isV ? player : this.Npc(this.m_finger);
    this.Say(line.audio, line.text, line.seconds, speaker, line.speaker, this.m_line + (this.m_phase == 4 ? 20 : 0));
    this.m_line += 1;
    this.Queue(n"line", line.seconds + line.gap);
  }

  private func Say(audio: CName, text: String, seconds: Float, speaker: ref<GameObject>, name: String, n: Int32) -> Void {
    let game = this.GetGameInstance();
    if NotEquals(audio, n"") { SlumlordVoice(game, audio, speaker); }
    let board = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(board) { return; }
    let line: scnDialogLineData;
    line.id = CreateCRUID(Cast<Uint64>(886400 + n));
    line.text = text;
    if IsDefined(speaker) {
      line.type = scnDialogLineType.Regular;
      line.speaker = speaker;
    } else {
      line.type = scnDialogLineType.OwnerlessRegular;
    }
    line.speakerName = name;
    line.isPersistent = false;
    line.duration = seconds;
    let lines: array<scnDialogLineData>;
    ArrayPush(lines, line);
    board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
    let hide = new SlumlordHideLineCallback();
    hide.id = line.id;
    GameInstance.GetDelaySystem(game).DelayCallback(hide, seconds + 0.25, false);
  }

  private func LookAtV(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>) -> Void {
    let look = new LookAtAddEvent();
    look.SetEntityTarget(player, n"pla_default_tgt", Vector4.EmptyVector());
    look.SetStyle(animLookAtStyle.Normal);
    look.request.limits.softLimitDegrees = 360.0;
    look.request.limits.hardLimitDegrees = 270.0;
    look.request.limits.backLimitDegrees = 210.0;
    look.request.limits.hardLimitDistance = GetLookAtLimitDistanceValue(animLookAtLimitDistanceType.None);
    look.request.calculatePositionInParentSpace = true;
    look.bodyPart = n"Eyes";
    let parts: array<LookAtPartRequest>;
    let head: LookAtPartRequest;
    head.partName = n"Head";
    head.weight = 0.1;
    head.suppress = 1.0;
    head.mode = 0;
    ArrayPush(parts, head);
    let chest: LookAtPartRequest;
    chest.partName = n"Chest";
    chest.weight = 0.2;
    chest.suppress = 0.0;
    chest.mode = 0;
    ArrayPush(parts, chest);
    look.SetAdditionalPartsArray(parts);
    npc.QueueEvent(look);
    this.m_lookAt = look;
  }

  private func StopLookAt() -> Void {
    let finger = this.Npc(this.m_finger);
    if IsDefined(finger) && IsDefined(this.m_lookAt) {
      LookAtRemoveEvent.QueueRemoveLookatEvent(finger, this.m_lookAt);
    }
    this.m_lookAt = null;
  }

  private func MoveTo(npc: ref<NPCPuppet>, target: Vector4, within: Float, type: moveMovementType, opt face: ref<GameObject>) -> Void {
    let world: WorldPosition;
    WorldPosition.SetVector4(world, target);
    let command = new AIMoveToCommand();
    AIPositionSpec.SetWorldPosition(command.movementTarget, world);
    command.movementType = type;
    if IsDefined(face) {
      AIPositionSpec.SetEntity(command.facingTarget, face);
      command.rotateEntityTowardsFacingTarget = true;
    }
    command.desiredDistanceFromTarget = within;
    command.finishWhenDestinationReached = true;
    command.ignoreInCombat = true;
    let ai = npc.GetAIControllerComponent();
    if IsDefined(ai) { ai.SendCommand(command); }
  }

  // ---- fight ----

  private func GoHostile() -> Void {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) || this.m_phase >= 3 { return; }
    this.m_phase = 3;
    this.m_ticks = 0;
    SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_wait", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
    SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_motel", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_goons", "gameJournalQuestObjective", gameJournalEntryState.Active, false);
    SlumlordBuyUp.Track(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_goons");
    for id in this.m_goons {
      let npc = this.Npc(id);
      if IsDefined(npc) {
        let agent = npc.GetAttitudeAgent();
        if IsDefined(agent) {
          agent.SetAttitudeGroup(TweakDBInterface.GetCharacterRecord(npc.GetRecordID()).BaseAttitudeGroup());
        }
        this.Attitude(npc, player, EAIAttitude.AIA_Hostile);
        TargetTrackingExtension.InjectThreat(npc, player);
      }
    }
    // Finger ducks out of the fight.
    let finger = this.Npc(this.m_finger);
    if IsDefined(finger) {
      this.StopLookAt();
      this.LeaveSpot(finger);
      this.MoveTo(finger, SlumlordMotelScene.HidePos(), 0.5, moveMovementType.Sprint);
    }
    SlumlordUi.Log("Conversation Overtime: fight on");
  }

  private func FightTick() -> Void {
    let down = 0;
    let i = 0;
    while i < ArraySize(this.m_goons) {
      let npc = this.Npc(this.m_goons[i]);
      if IsDefined(npc) {
        this.m_goonSeen[i] = true;
        if npc.IsDead() || ScriptedPuppet.IsDefeated(npc) { down += 1; }
      } else if this.m_goonSeen[i] || this.m_ticks > 15 {
        down += 1;   // gone after being seen (or never spawned at all)
      }
      i += 1;
    }
    // Keep Finger out of it: neutral, and back to his hiding place if the fight shoved him off it.
    let finger = this.Npc(this.m_finger);
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(finger) && IsDefined(player) {
      this.Attitude(finger, player, EAIAttitude.AIA_Neutral);
      if this.m_ticks % 5 == 0 && Vector4.Distance(finger.GetWorldPosition(), SlumlordMotelScene.HidePos()) > 2.0 {
        this.MoveTo(finger, SlumlordMotelScene.HidePos(), 0.5, moveMovementType.Sprint);
      }
    }
    if down >= ArraySize(this.m_goons) {
      this.m_phase = 4;
      this.m_ticks = 0;
      this.m_line = 0;
      SlumlordJournal.Set(this.GetGameInstance(), SlumlordConversationOvertime.Phase() + "/slumlord_co_goons", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, false);
      SlumlordUi.Log("Conversation Overtime: goons down, truce");
      this.Queue(n"truce", 2.5);
    }
  }

  // ---- truce ----

  private func StartTruce() -> Void {
    if this.m_phase != 4 { return; }
    let player = GetPlayer(this.GetGameInstance());
    let finger = this.Npc(this.m_finger);
    if IsDefined(player) && IsDefined(finger) {
      this.LookAtV(finger, player);
      this.Approach();
    }
    this.Queue(n"line", 0.2);
  }

  private func Finish() -> Void {
    let game = this.GetGameInstance();
    this.m_phase = 5;
    this.m_ticks = 0;
    let finger = SlumlordFinger.GetInstance(game);
    if IsDefined(finger) { finger.Win(); }
    // Finger walks back toward the motel entrance and on past it.
    let npc = this.Npc(this.m_finger);
    if IsDefined(npc) {
      this.StopLookAt();
      let away = SlumlordConversationOvertime.MotelEntrance() - npc.GetWorldPosition();
      away.Z = 0.0;
      this.MoveTo(npc, npc.GetWorldPosition() + Vector4.Normalize(away) * 60.0, 2.0, moveMovementType.Walk);
    }
    SlumlordUi.Log("Conversation Overtime: truce done, Finger walks");
  }

  // ---- clearing the area ----
  // Las Palapas is dense: every vanilla NPC near Finger's spot is destroyed (the game refuses despawn
  // requests for some, Fight.reds 2026-11-18), every second until Finger walks off.

  private func IsOurs(id: EntityID) -> Bool {
    if Equals(id, this.m_finger) { return true; }
    for g in this.m_goons {
      if Equals(id, g) { return true; }
    }
    return false;
  }

  private func ClearLocals(player: ref<PlayerPuppet>) -> Void {
    let center = SlumlordConversationOvertime.FingerSpot();
    let query = TSQ_NPC();
    query.testedSet = TargetingSet.Complete;
    query.maxDistance = SlumlordMotelScene.SpawnDistance() + 30.0;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(this.GetGameInstance()).GetTargetParts(player, query, parts);
    let done: array<EntityID>;
    for part in parts {
      let comp = TS_TargetPartInfo.GetComponent(part);
      let npc = IsDefined(comp) ? comp.GetEntity() as NPCPuppet : null;
      if IsDefined(npc) && !ArrayContains(done, npc.GetEntityID()) {
        ArrayPush(done, npc.GetEntityID());
        if !this.IsOurs(npc.GetEntityID()) && !npc.IsPlayerCompanion()
            && Vector4.Distance(npc.GetWorldPosition(), center) < SlumlordMotelScene.ClearRadius() {
          if !ArrayContains(this.m_clearIds, npc.GetEntityID()) { ArrayPush(this.m_clearIds, npc.GetEntityID()); }
          EntityGameInterface.Destroy(npc.GetEntity());
        }
      }
    }
  }

  // ---- cleanup ----

  private func Abandon(why: String) -> Void {
    let game = this.GetGameInstance();
    let wasBusy = this.m_phase >= 2;
    this.DeleteScene();
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.BikeTag());
    this.m_spawned = false;
    this.m_phase = 0;
    let finger = SlumlordFinger.GetInstance(game);
    if wasBusy && IsDefined(finger) && finger.GetStage() == 3 {
      SlumlordJournal.Set(game, SlumlordConversationOvertime.Phase() + "/slumlord_co_goons", "gameJournalQuestObjective", gameJournalEntryState.Inactive, false);
      finger.RefreshObjectives();
    }
    SlumlordUi.Log("Conversation Overtime: motel scene cleared (" + why + ")");
  }

  private func DeleteScene() -> Void {
    SlumlordForgetVoice(this.GetGameInstance(), this.m_finger);
    this.m_lookAt = null;
    this.m_spotCommand = null;
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordMotelScene.Tag());
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
    } else if Equals(action, n"line") {
      this.NextLine();
    } else if Equals(action, n"step") {
      this.Approach();
    } else if Equals(action, n"truce") {
      this.StartTruce();
    }
  }

  public func Debug_ToggleAnyTime() -> Bool {
    this.m_anyTime = !this.m_anyTime;
    return this.m_anyTime;
  }

  public func Debug_Clear() -> Void {
    this.Abandon("debug");
  }

  public func Debug_State() -> String {
    let player = GetPlayer(this.GetGameInstance());
    let dist = IsDefined(player) ? Vector4.Distance(player.GetWorldPosition(), SlumlordConversationOvertime.FingerSpot()) : -1.0;
    let alive = 0;
    for id in this.m_goons {
      let npc = this.Npc(id);
      if IsDefined(npc) && !npc.IsDead() && !ScriptedPuppet.IsDefeated(npc) { alive += 1; }
    }
    return "motel phase=" + IntToString(this.m_phase) + " spawned=" + (this.m_spawned ? "yes" : "no")
      + " any time=" + (this.m_anyTime ? "yes" : "no") + " dist=" + FloatToStringPrec(dist, 0) + "m"
      + " goons up=" + IntToString(alive) + "/" + IntToString(ArraySize(this.m_goons))
      + " cleared NPCs=" + IntToString(ArraySize(this.m_clearIds)) + " | " + SlumlordMotelScene.RecordReport();
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
