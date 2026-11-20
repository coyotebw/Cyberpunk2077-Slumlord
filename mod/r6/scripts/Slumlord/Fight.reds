// Watson boss arc (design doc 4.8), beats 2-4: Karl's texts, the Harbor Safehouse confrontation, the win.
// Quest "Million Dollar Baby" (journal id slumlord_final_cut, kept so saves carry over).
//
// Texts, quest and objectives are journal entries from Slumlord.archive (slumlord\journal\slumlord.journal,
// texts in slumlord\localization\en-us.json, both loaded by Slumlord.archive.xl), revealed from here with
// JournalManager.ChangeEntryState, the way quest nodes do it. The map pin is a script pin (quest style):
// a journal pin needs an entity placed in the world data.
// Oshima and the Maelstromers are Codeware DynamicEntitySystem spawns at the property's captured position.
// Oshima never fights: invulnerable, he Sandevistan-dashes from side to side near the door (the game's NPC
// Sandevistan time dilation, ease curves and FX names, driven from here), then sprints off with his line.
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
  private let m_pinId: NewMappinID;
  private let m_pinOn: Bool;

  private let m_spawned: Bool;
  private let m_oshima: EntityID;
  private let m_gangers: array<EntityID>;
  private let m_configured: array<Bool>;       // per ganger: neutral attitude applied
  private let m_oshimaReady: Bool;
  private let m_phase: Int32;                  // 0 none, 1 waiting at the door, 2 talking, 3 fighting, 4 won
  private let m_line: Int32;
  private let m_fightTicks: Int32;
  private let m_oshimaGone: Bool;
  private let m_fleeTicks: Int32;
  private let m_dodgeSide: Float;
  private let m_lookAt: ref<LookAtAddEvent>;
  private let m_spotCommands: array<ref<AIUseWorkspotCommand>>;   // per ganger, then Oshima last
  private let m_clearIds: array<EntityID>;    // vanilla NPCs at the door we destroyed

  public static func GetInstance(game: GameInstance) -> ref<SlumlordFight> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordFight") as SlumlordFight;
  }

  public static func Property() -> CName { return n"wat_harbor_safehouse"; }
  public static func DoorYaw() -> Float { return 27.1; }          // V's facing when the position was captured
  public static func SpawnDistance() -> Float { return 150.0; }
  public static func TalkDistance() -> Float { return 12.0; }
  public static func ClearRadius() -> Float { return 30.0; }      // vanilla gang NPCs this close to the door are removed
  public static func LeaveDistance() -> Float { return 230.0; }
  public static func TextGapSeconds() -> Float { return 8.0; }
  public static func OshimaRunsAfter() -> Int32 { return 16; }     // seconds into the fight
  public static func Tag() -> CName { return n"SlumlordFinalCut"; }
  public static func DoneFact() -> String { return "slumlord_wat_boss_done"; }
  public static func RewardXP() -> Int32 { return 1000; }
  public static func ThanksDelay() -> Float { return 20.0; }

  // Scene spots, captured in game 2026-11-18. Index 0-3: the gangers in Gangers() order, 4: Oshima.
  // Each is an AI spot node in slumlord_markers.streamingsector (tools/journal/make_world.py) running a
  // vanilla workspot: knocking, welding, smoking, arguing; Oshima arms crossed.
  public static func SpotRef(i: Int32) -> String {
    let names: array<String> = ["knocker", "welder", "smoker", "talker", "oshima"];
    return "$/slumlord/final_cut/#slumlord_fc_spot_" + names[i];
  }

  public static func SpotPos(i: Int32) -> Vector4 {
    switch i {
      case 0: return new Vector4(-2014.59, 2619.14, 18.36, 1.0);
      case 1: return new Vector4(-2012.98, 2619.79, 18.36, 1.0);
      case 2: return new Vector4(-2014.85, 2613.56, 18.15, 1.0);
      case 3: return new Vector4(-2013.11, 2614.17, 18.15, 1.0);
      default: return new Vector4(-2014.41, 2612.43, 18.17, 1.0);
    }
  }

  public static func SpotYaw(i: Int32) -> Float {
    let yaws: array<Float> = [28.7, 100.9, -106.2, 130.1, -15.5];
    return yaws[i];
  }

  public static func Gangers() -> array<TweakDBID> {
    return [t"Character.maelstrom_grunt2_melee2_machete_ma", t"Character.maelstrom_grunt1_ranged1_lexington_ma",
            t"Character.maelstrom_grunt2_ranged2_ajax_wa", t"Character.maelstrom_grunt1_ranged1_copperhead_ma"];
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_ticking = false;
    this.m_textQueued = false;
    this.m_pinOn = false;
    this.m_spawned = false;
    this.m_phase = 0;
    this.DeleteScene();
    // Saves from before the quest started at the call: show it now.
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    if this.m_stage == 0 && !this.m_started && IsDefined(boss) && boss.IsCallDone() {
      this.StartQuest(false);
    }
    if this.m_stage == 3 {
      this.UnlockOshima();
    }
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
    this.m_stage = 2;
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
    if this.m_phase < 2 {
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
    if IsDefined(player) {
      let dist = Vector4.Distance(player.GetWorldPosition(), SlumlordPositions.Get(SlumlordFight.Property()));
      if !this.m_spawned && dist < SlumlordFight.SpawnDistance() {
        this.Spawn();
      } else if this.m_spawned && this.m_phase < 4 && dist > SlumlordFight.LeaveDistance() {
        this.Abandon();
      } else if this.m_spawned {
        this.Configure(player);
        if this.m_phase <= 2 {
          this.ClearLocals(player);
        }
        if (this.m_phase == 1 || this.m_phase == 2) && (player.IsInCombat() || this.AnyGangerHurt()) {
          this.GoHostile();   // V opened fire first: skip the talk
        } else if this.m_phase == 1 && this.m_oshimaReady && dist < SlumlordFight.TalkDistance() {
          this.StartTalk();
        } else if this.m_phase == 3 {
          this.FightTick(player);
        }
      }
    }
    if this.m_stage == 2 {
      this.m_ticking = true;
      this.Queue(n"tick", 1.0);
    }
  }

  // ---- spawning ----

  private func Spawn() -> Void {
    ArrayClear(this.m_gangers);
    ArrayClear(this.m_configured);
    ArrayClear(this.m_spotCommands);
    let i = 0;
    for record in SlumlordFight.Gangers() {
      ArrayPush(this.m_gangers, this.SpawnRecord(record, SlumlordFight.SpotPos(i), SlumlordFight.SpotYaw(i)));
      ArrayPush(this.m_configured, false);
      ArrayPush(this.m_spotCommands, null);
      i += 1;
    }
    ArrayPush(this.m_spotCommands, null);   // Oshima's
    this.m_oshima = this.SpawnRecord(t"Character.q005_hideyoshi_oshima", SlumlordFight.SpotPos(4), SlumlordFight.SpotYaw(4));
    this.m_oshimaReady = false;
    this.m_oshimaGone = false;
    this.m_spawned = true;
    this.m_phase = 1;
    this.m_line = 0;
    SlumlordUi.Log("Million Dollar Baby: spawned Oshima and " + IntToString(ArraySize(this.m_gangers)) + " Maelstromers");
  }

  private func SpawnRecord(record: TweakDBID, pos: Vector4, yaw: Float) -> EntityID {
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
    spec.tags = [SlumlordFight.Tag()];
    return GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
  }

  public static func YawDir(yaw: Float) -> Vector4 {
    let rad = Deg2Rad(yaw);
    return new Vector4(-SinF(rad), CosF(rad), 0.0, 0.0);
  }

  private func Npc(id: EntityID) -> ref<NPCPuppet> {
    return GameInstance.GetDynamicEntitySystem().GetEntity(id) as NPCPuppet;
  }

  // Spawns finish asynchronously: keep everyone calm until the talk is over, and Oshima unkillable.
  private func Configure(player: ref<PlayerPuppet>) -> Void {
    if this.m_phase <= 2 {
      let i = 0;
      while i < ArraySize(this.m_gangers) {
        let npc = this.Npc(this.m_gangers[i]);
        if IsDefined(npc) {
          if !this.m_configured[i] {
            // Their own group (maelstrom) is hostile to V on sight in 2.5; park them in the game's
            // "neutral" group until Oshima's "Kill him!".
            let agent = npc.GetAttitudeAgent();
            if IsDefined(agent) {
              agent.SetAttitudeGroup(n"neutral");
            }
            this.EnterSpot(npc, i);
            this.m_configured[i] = true;
          }
          this.Attitude(npc, player, EAIAttitude.AIA_Neutral);
        }
        i += 1;
      }
    }
    if !this.m_oshimaReady {
      let oshima = this.Npc(this.m_oshima);
      if IsDefined(oshima) {
        StatusEffectHelper.ApplyStatusEffect(oshima, t"BaseStatusEffect.Invulnerable");
        // The status effect alone didn't stop damage on Finger (2026-11-20); god mode does.
        GameInstance.GetGodModeSystem(this.GetGameInstance()).AddGodMode(oshima.GetEntityID(), gameGodModeType.Invulnerable, n"SlumlordFight");
        this.Attitude(oshima, player, EAIAttitude.AIA_Neutral);
        if this.m_phase == 1 {
          this.EnterSpot(oshima, 4);
        }
        this.m_oshimaReady = true;
      }
    }
  }

  // ---- workspots ----

  private func EnterSpot(npc: ref<NPCPuppet>, i: Int32) -> Void {
    let ai = npc.GetAIControllerComponent();
    if !IsDefined(ai) { return; }
    let command = new AIUseWorkspotCommand();
    command.workspotNode = CreateNodeRef(SlumlordFight.SpotRef(i));
    command.moveToWorkspot = true;
    command.movementType = moveMovementType.Walk;
    command.continueInCombat = false;
    ai.SendCommand(command);
    this.m_spotCommands[i] = command;
  }

  private func LeaveSpot(npc: ref<NPCPuppet>, i: Int32) -> Void {
    if !IsDefined(npc) { return; }
    let command = this.m_spotCommands[i];
    let ai = npc.GetAIControllerComponent();
    if IsDefined(command) && IsDefined(ai) {
      ai.CancelCommand(command);
    }
    this.m_spotCommands[i] = null;
    let workspots = GameInstance.GetWorkspotSystem(this.GetGameInstance());
    if workspots.IsActorInWorkspot(npc) {
      workspots.SendFastExitSignal(npc);
    }
  }

  private func SpotsInUse() -> String {
    if !this.m_spawned { return "-"; }
    let workspots = GameInstance.GetWorkspotSystem(this.GetGameInstance());
    let out = "";
    let i = 0;
    while i < 5 {
      let npc = i < 4 ? this.Npc(this.m_gangers[i]) : this.Npc(this.m_oshima);
      out += IsDefined(npc) ? (workspots.IsActorInWorkspot(npc) ? "Y" : "n") : "?";
      i += 1;
    }
    return out + " (knock weld smoke talk oshima)";
  }

  // V opened fire before the talk finished.
  private func AnyGangerHurt() -> Bool {
    let pools = GameInstance.GetStatPoolsSystem(this.GetGameInstance());
    for id in this.m_gangers {
      let npc = this.Npc(id);
      if IsDefined(npc) {
        if npc.IsDead() || pools.GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true) < 99.0 {
          return true;
        }
      }
    }
    return false;
  }

  private func Attitude(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>, attitude: EAIAttitude) -> Void {
    let agent = npc.GetAttitudeAgent();
    let pa = player.GetAttitudeAgent();
    if !IsDefined(agent) || !IsDefined(pa) { return; }
    agent.SetAttitudeTowards(pa, attitude);
    pa.SetAttitudeTowards(agent, attitude);
  }

  // ---- the talk ----

  private func StartTalk() -> Void {
    let game = this.GetGameInstance();
    this.m_phase = 2;
    this.m_line = 0;
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Succeeded);
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Active);
    SlumlordJournal.Track(game, "slumlord_fc_fight");
    let player = GetPlayer(game);
    let oshima = this.Npc(this.m_oshima);
    if IsDefined(player) && IsDefined(oshima) {
      this.LookAtV(oshima, player);
      this.LeaveSpot(oshima, 4);
      this.Queue(n"oshimastep", 1.0);   // after the exit animation
    }
    this.Queue(n"line", 0.3);
  }

  private func OshimaStep() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    let oshima = this.Npc(this.m_oshima);
    if !IsDefined(player) || !IsDefined(oshima) || this.m_phase != 2 { return; }
    let toV = player.GetWorldPosition() - oshima.GetWorldPosition();
    toV.Z = 0.0;
    let step = MinF(2.5, MaxF(0.0, Vector4.Length(toV) - 4.0));   // a few steps, stop 4 m short of V
    this.MoveTo(oshima, oshima.GetWorldPosition() + Vector4.Normalize(toV) * step, 0.3, moveMovementType.Walk, player);
  }

  // Head and eyes follow V (the game's own look-at, as its reaction system uses).
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

  // Turn in place to face V (a zero-length move with V as the facing target).
  private func FaceV(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>) -> Void {
    this.MoveTo(npc, npc.GetWorldPosition(), 1.0, moveMovementType.Walk, player);
  }

  private func NextLine() -> Void {
    if this.m_phase != 2 { return; }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let male = IsDefined(player) && Equals(player.GetResolvedGenderName(), n"Male");
    let oshima = this.Npc(this.m_oshima);
    let n = this.m_line;
    this.m_line += 1;
    switch n {
      case 0:
        this.Say(n"slumlord_oshima_fight_01", "V. I told you we'd be seeing each other again.", 2.30, oshima, "Oshima", 0);
        this.Queue(n"line", 2.30 + 0.5);
        break;
      case 1:
        this.Say(male ? n"slumlord_v_fight_01_m" : n"slumlord_v_fight_01_f", "What the fuck…?", male ? 1.85 : 1.89, player, "V", 1);
        this.Queue(n"line", (male ? 1.85 : 1.89) + 0.5);
        break;
      case 2:
        if IsDefined(oshima) && IsDefined(player) { this.FaceV(oshima, player); }
        this.Say(n"slumlord_oshima_fight_02", "I need this place to film a scene for Death Stranding 12. Now get lost, you're ruining the shot.", 8.40, oshima, "Oshima", 2);
        this.Queue(n"line", 8.40 + 0.3);
        break;
      case 3:
        this.Say(n"slumlord_oshima_fight_03", male ? "Kill him!" : "Kill her!", 1.28, oshima, "Oshima", 3);
        this.Queue(n"line", 0.6);
        break;
      default:
        this.GoHostile();
    }
  }

  private func Say(audio: CName, text: String, seconds: Float, speaker: ref<GameObject>, name: String, n: Int32) -> Void {
    let game = this.GetGameInstance();
    SlumlordVoice(game, audio, speaker);
    let board = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(board) { return; }
    let line: scnDialogLineData;
    line.id = CreateCRUID(Cast<Uint64>(885400 + n));
    line.text = text;
    // The subtitle HUD needs a speaker object for Regular lines; fall back to ownerless if one is missing.
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

  // ---- the fight ----

  private func GoHostile() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) { return; }
    this.m_phase = 3;
    this.m_fightTicks = 0;
    let k = 0;
    while k < ArraySize(this.m_gangers) {
      this.LeaveSpot(this.Npc(this.m_gangers[k]), k);
      k += 1;
    }
    this.LeaveSpot(this.Npc(this.m_oshima), 4);
    this.m_dodgeSide = 1.0;
    SlumlordJournal.Objective(this.GetGameInstance(), "slumlord_fc_go", gameJournalEntryState.Succeeded);
    SlumlordJournal.Objective(this.GetGameInstance(), "slumlord_fc_fight", gameJournalEntryState.Active);
    SlumlordJournal.Track(this.GetGameInstance(), "slumlord_fc_fight");
    for id in this.m_gangers {
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
    SlumlordUi.Log("Million Dollar Baby: fight on");
  }

  private func FightTick(player: ref<PlayerPuppet>) -> Void {
    this.m_fightTicks += 1;
    let down = 0;
    for id in this.m_gangers {
      let npc = this.Npc(id);
      if !IsDefined(npc) || npc.IsDead() || ScriptedPuppet.IsDefeated(npc) {
        down += 1;
      }
    }
    if !this.m_oshimaGone && (this.m_fightTicks >= SlumlordFight.OshimaRunsAfter() || down > 0) {
      this.OshimaRuns(player);
    } else if !this.m_oshimaGone && this.m_fightTicks % 3 == 1 {
      this.Dodge(player);
    }
    if this.m_oshimaGone {
      this.m_fleeTicks += 1;
      if this.m_fleeTicks == 8 {
        this.DeleteOshima();
      }
    }
    if down == ArraySize(this.m_gangers) {
      this.Win();
    }
  }

  // One Sandevistan dash, 4 m across V's line of fire, kept within 7 m of the door.
  private func Dodge(player: ref<PlayerPuppet>) -> Void {
    let oshima = this.Npc(this.m_oshima);
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

  private func OshimaRuns(player: ref<PlayerPuppet>) -> Void {
    this.m_oshimaGone = true;
    this.m_fleeTicks = 0;
    let oshima = this.Npc(this.m_oshima);
    if !IsDefined(oshima) { return; }
    this.Say(n"slumlord_oshima_flee_01", "This isn't over, V!", 2.63, oshima, "Oshima", 4);
    if IsDefined(this.m_lookAt) {
      LookAtRemoveEvent.QueueRemoveLookatEvent(oshima, this.m_lookAt);
      this.m_lookAt = null;
    }
    // Away from V, 60 m out.
    let away = oshima.GetWorldPosition() - player.GetWorldPosition();
    away.Z = 0.0;
    let target = oshima.GetWorldPosition() + Vector4.Normalize(away) * 60.0;
    TimeDilationHelper.SetIndividualTimeDilation(oshima, n"slumlordSandevistan", 2.5, 6.0, n"SandevistanEaseIn", n"SandevistanEaseOut");
    this.MoveTo(oshima, target, 2.0);
    SlumlordUi.Log("Million Dollar Baby: Oshima runs");
  }

  private func Win() -> Void {
    let game = this.GetGameInstance();
    this.m_phase = 4;
    this.m_stage = 3;
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Succeeded);
    SlumlordJournal.Set(game, SlumlordJournal.Phase(), "gameJournalQuestPhase", gameJournalEntryState.Succeeded, false);
    SlumlordJournal.Set(game, SlumlordJournal.Quest(), "gameJournalQuest", gameJournalEntryState.Succeeded, true);
    this.SetPin(false);
    GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordFight.DoneFact(), 1);
    this.UnlockOshima();   // he joins V as Contractor #16 (design doc 4.4)
    RPGManager.AwardExperienceInstantly(GetPlayer(game), SlumlordFight.RewardXP(), gamedataProficiencyType.Level);
    this.Queue(n"thanks", SlumlordFight.ThanksDelay());
    if !this.m_oshimaGone {
      this.DeleteOshima();
    } else if this.m_fleeTicks < 8 {
      this.Queue(n"cleanup", 6.0);   // let him finish running out of sight
    }
    SlumlordUi.Log("Million Dollar Baby: won, Watson dominated");
  }

  private func SendThanks() -> Void {
    if this.m_stage != 3 || this.m_thanked { return; }
    this.m_thanked = true;
    SlumlordJournal.Set(this.GetGameInstance(), SlumlordJournal.Thread() + "/slumlord_karl_06", "gameJournalPhoneMessage", gameJournalEntryState.Active, true);
    SlumlordUi.Log("Million Dollar Baby: Karl says thanks");
  }

  // V walked away mid-encounter: clear the scene, re-arm.
  private func Abandon() -> Void {
    let game = this.GetGameInstance();
    this.DeleteScene();
    this.m_spawned = false;
    this.m_phase = 0;
    SlumlordJournal.Objective(game, "slumlord_fc_fight", gameJournalEntryState.Inactive);
    SlumlordJournal.Objective(game, "slumlord_fc_go", gameJournalEntryState.Active);
    SlumlordJournal.Track(game, "slumlord_fc_go");
    SlumlordUi.Log("Million Dollar Baby: V left, scene cleared");
  }

  private func DeleteOshima() -> Void {
    SlumlordForgetVoice(this.GetGameInstance(), this.m_oshima);
    GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_oshima);
  }

  private func DeleteScene() -> Void {
    GameInstance.GetGodModeSystem(this.GetGameInstance()).RemoveGodMode(this.m_oshima, gameGodModeType.Invulnerable, n"SlumlordFight");
    SlumlordForgetVoice(this.GetGameInstance(), this.m_oshima);
    this.m_lookAt = null;
    GameInstance.GetDynamicEntitySystem().DeleteTagged(SlumlordFight.Tag());
  }

  // ---- the gang already hanging out at the Safehouse ----
  // A vanilla group of Maelstromers idles at the door (they sit in workspots). The game refuses a despawn request
  // for them and teleporting does not move them (2026-11-18 log), so their entities are destroyed outright.
  // Repeated every tick until the fight starts, in case the community spawns them again.

  private func IsOurs(id: EntityID) -> Bool {
    if Equals(id, this.m_oshima) { return true; }
    for g in this.m_gangers {
      if Equals(id, g) { return true; }
    }
    return false;
  }

  private func ClearLocals(player: ref<PlayerPuppet>) -> Void {
    let game = this.GetGameInstance();
    let door = SlumlordPositions.Get(SlumlordFight.Property());
    let query = TSQ_NPC();
    query.testedSet = TargetingSet.Complete;
    query.maxDistance = SlumlordFight.SpawnDistance() + 30.0;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(game).GetTargetParts(player, query, parts);
    let done: array<EntityID>;    // each NPC has several target parts
    for part in parts {
      let comp = TS_TargetPartInfo.GetComponent(part);
      let npc = IsDefined(comp) ? comp.GetEntity() as NPCPuppet : null;
      if IsDefined(npc) && !ArrayContains(done, npc.GetEntityID()) {
        ArrayPush(done, npc.GetEntityID());
        if !npc.IsDead() && !this.IsOurs(npc.GetEntityID())
            && Vector4.Distance(npc.GetWorldPosition(), door) < SlumlordFight.ClearRadius() && SlumlordFight.IsMaelstrom(npc) {
          this.RemoveLocal(npc);
        }
      }
    }
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

  // Every NPC near the door that isn't ours, for the CET readout.
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
        if d < 45.0 && !this.IsOurs(npc.GetEntityID()) {
          out += " [" + FloatToStringPrec(d, 0) + "m " + SlumlordFight.GangInfo(npc) + (npc.IsDead() ? " dead" : "") + "]";
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
    } else {
      SlumlordUi.Log("Million Dollar Baby: vanilla Maelstromer still there after destroy, retrying");
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
    } else if Equals(action, n"line") {
      this.NextLine();
    } else if Equals(action, n"check") {
      this.CheckTrigger();
    } else if Equals(action, n"thanks") {
      this.SendThanks();
    } else if Equals(action, n"oshimastep") {
      this.OshimaStep();
    } else if Equals(action, n"pincheck") {
      SlumlordUi.Log("Million Dollar Baby: pin after 5 s: " + SlumlordFight.JournalPinState(this.GetGameInstance()));
    } else if Equals(action, n"cleanup") {
      this.DeleteOshima();
    }
  }

  public func Debug_StartTexts() -> Void {
    this.DeleteScene();
    this.m_spawned = false;
    this.m_phase = 0;
    this.m_stage = 0;
    this.BeginTexts(2.0);
  }

  public func Debug_Reset() -> Void {
    let game = this.GetGameInstance();
    this.DeleteScene();
    this.SetPin(false);
    this.m_stage = 0;
    this.m_textsSent = 0;
    this.m_spawned = false;
    this.m_phase = 0;
    this.m_started = false;
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
      + " started=" + (this.m_started ? "yes" : "no") + " stage=" + IntToString(this.m_stage) + " texts=" + IntToString(this.m_textsSent) + " phase=" + IntToString(this.m_phase)
      + " spawned=" + (this.m_spawned ? "yes" : "no")
      + " in workspot=" + this.SpotsInUse()
      + " pin=" + SlumlordFight.JournalPinState(this.GetGameInstance())
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
