// Watson boss arc (design doc 4.8), beat 1: Oshima's call after V's first Watson purchase.
//
// Built on the game's own phone. PhoneSystem rings V with a caller id that is not a phone contact
// (no journal entry needed), so the phone HUD shows a blank name and the "unknown" avatar; the wraps at
// the bottom fill in "UNKNOWN" while it rings and Oshima's name once V picks up. PhoneSystem reports
// pickup through SetPhoneFact (phonecall_<caller>_with_player = questPhoneTalkingState).
// Voice: Audioware sfx (r6/audioware/Slumlord/slumlord.yml), played 2D; Oshima's lines carry a baked-in
// holocall effect (tools/voice/holo_fx.py, preset holo), V's are dry. Subtitles through the
// UIGameData.ShowDialogLine blackboard (the same pattern as Cerberus Ride).
module Slumlord

public class SlumlordBoss extends ScriptableSystem {
  private persistent let m_watCallPending: Bool;   // first Watson property bought, call not taken yet
  private persistent let m_watCallDone: Bool;      // Oshima's call finished

  private let m_callState: Int32;                  // 0 idle, 1 ringing, 2 talking
  private let m_line: Int32;
  private let m_attemptQueued: Bool;

  public static func GetInstance(game: GameInstance) -> ref<SlumlordBoss> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordBoss") as SlumlordBoss;
  }

  public static func CallerId() -> CName { return n"slumlord_unknown_caller"; }
  public static func CallDelaySeconds() -> Float { return 45.0; }     // after the purchase: let V leave the terminal
  public static func RetrySeconds() -> Float { return 30.0; }         // V busy (combat, another call)
  public static func MissedRetrySeconds() -> Float { return 120.0; }  // V let it ring out
  public static func CallDoneFact() -> String { return "slumlord_wat_call_done"; }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_callState = 0;
    this.m_attemptQueued = false;
    if this.m_watCallPending && !this.m_watCallDone {
      this.ScheduleAttempt(60.0);
    }
  }

  // ---- triggers ----

  public func OnPropertyBought(def: ref<SlumlordPropertyDef>) -> Void {
    if !IsDefined(def) || !Equals(def.districtId, n"watson") { return; }
    if this.m_watCallDone || this.m_watCallPending { return; }
    this.m_watCallPending = true;
    SlumlordUi.Log("Oshima call: first Watson purchase, ringing in " + FloatToStringPrec(SlumlordBoss.CallDelaySeconds(), 0) + " s");
    this.ScheduleAttempt(SlumlordBoss.CallDelaySeconds());
  }

  public func Debug_RingNow() -> Void {
    this.m_watCallDone = false;
    this.m_watCallPending = true;
    this.m_callState = 0;
    this.TryRing();
  }

  public func Debug_Reset() -> Void {
    this.m_watCallDone = false;
    this.m_watCallPending = false;
    this.m_callState = 0;
    GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFactStr(SlumlordBoss.CallDoneFact(), 0);
  }

  public func Debug_State() -> String {
    return "pending=" + (this.m_watCallPending ? "yes" : "no") + " done=" + (this.m_watCallDone ? "yes" : "no") + " state=" + IntToString(this.m_callState);
  }

  // ---- ringing ----

  private func ScheduleAttempt(seconds: Float) -> Void {
    if this.m_attemptQueued { return; }
    this.m_attemptQueued = true;
    this.Queue(n"attempt", seconds);
  }

  private func Queue(action: CName, seconds: Float) -> Void {
    let cb = new SlumlordBossCallback();
    cb.system = this;
    cb.action = action;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, seconds, false);
  }

  public func OnCallback(action: CName) -> Void {
    if Equals(action, n"attempt") {
      this.m_attemptQueued = false;
      this.TryRing();
    } else if Equals(action, n"line") {
      this.PlayNextLine();
    } else if Equals(action, n"hangup") {
      this.HangUp();
    }
  }

  private func TryRing() -> Void {
    if !this.m_watCallPending || this.m_watCallDone || this.m_callState != 0 { return; }
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) || player.IsInCombat() || this.OtherCallActive() {
      this.ScheduleAttempt(SlumlordBoss.RetrySeconds());
      return;
    }
    this.m_callState = 1;
    this.SendCall(questPhoneCallPhase.IncomingCall);
    SlumlordUi.Log("Oshima call: ringing");
  }

  private func OtherCallActive() -> Bool {
    let info = SlumlordBoss.CurrentCall(this.GetGameInstance());
    if Equals(info.contactName, SlumlordBoss.CallerId()) { return false; }
    return Equals(info.callPhase, questPhoneCallPhase.IncomingCall) || Equals(info.callPhase, questPhoneCallPhase.StartCall);
  }

  public static func CurrentCall(game: GameInstance) -> PhoneCallInformation {
    let board = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_ComDevice);
    let info: PhoneCallInformation;
    if IsDefined(board) {
      info = FromVariant<PhoneCallInformation>(board.GetVariant(GetAllBlackboardDefs().UI_ComDevice.PhoneCallInformation));
    }
    return info;
  }

  private func SendCall(phase: questPhoneCallPhase) -> Void {
    let request = new questTriggerCallRequest();
    request.caller = SlumlordBoss.CallerId();
    request.addressee = n"player";
    request.callPhase = phase;
    request.callMode = questPhoneCallMode.Audio;
    request.isPlayerTriggered = false;
    request.isRejectable = false;
    request.showAvatar = false;
    request.visuals = questPhoneCallVisuals.Default;
    GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PhoneSystem").QueueRequest(request);
  }

  // PhoneSystem reports every state change of our call here (see the SetPhoneFact wrap).
  public func OnPhoneState(state: questPhoneTalkingState) -> Void {
    if this.m_callState == 1 && Equals(state, questPhoneTalkingState.Talking) {
      this.m_callState = 2;
      this.m_line = 0;
      SlumlordUi.Log("Oshima call: picked up");
      this.SendCall(questPhoneCallPhase.StartCall);
      this.Queue(n"line", 0.8);
      return;
    }
    if this.m_callState == 1 && (Equals(state, questPhoneTalkingState.Ended) || Equals(state, questPhoneTalkingState.Rejected)) {
      this.m_callState = 0;
      SlumlordUi.Log("Oshima call: missed, calling again later");
      this.ScheduleAttempt(SlumlordBoss.MissedRetrySeconds());
    }
  }

  // ---- the conversation ----

  private func PlayNextLine() -> Void {
    if this.m_callState != 2 { return; }
    let n = this.m_line;
    this.m_line += 1;
    let player = GetPlayer(this.GetGameInstance());
    let male = IsDefined(player) && Equals(player.GetResolvedGenderName(), n"Male");
    let audio: CName;
    let text: String;
    let seconds: Float;
    let speaker: String = "Oshima";
    let gap: Float = 0.9;
    switch n {
      case 0:
        audio = n"slumlord_oshima_call_01";
        text = "V. Hideyoshi Oshima. I hear you've been buying up my locations.";
        seconds = 7.16;
        break;
      case 1:
        audio = n"slumlord_oshima_call_02";
        text = "Those buildings are sets for my braindances. Real damp, real despair. You can't build that in a studio. You're ruining the light.";
        seconds = 12.78;
        break;
      case 2:
        audio = n"slumlord_oshima_call_03";
        text = "So, an offer. I'll toss you five hundred eddies. Give up collecting rent and go back to shooting people.";
        seconds = 9.71;
        gap = 0.6;
        break;
      case 3:
        audio = male ? n"slumlord_v_call_01_m" : n"slumlord_v_call_01_f";
        text = "No.";
        seconds = male ? 1.23 : 0.96;
        speaker = "V";
        gap = 0.6;
        break;
      case 4:
        audio = n"slumlord_oshima_call_04";
        text = "Hmph. Big mistake. I'll be seeing you, V.";
        seconds = 4.61;
        break;
      default:
        this.Queue(n"hangup", 0.2);
        return;
    }
    this.Say(audio, text, seconds, speaker, n);
    this.Queue(n"line", seconds + gap);
  }

  private func Say(audio: CName, text: String, seconds: Float, speaker: String, n: Int32) -> Void {
    let game = this.GetGameInstance();
    GameInstance.GetAudioSystem(game).Play(audio);
    let board = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(board) { return; }
    // The subtitle HUD drops a Regular line without a speaker object (IsMainDialogLine): V's line is
    // spoken by V's puppet; Oshima is not in the world, so his lines are OwnerlessRegular.
    let line: scnDialogLineData;
    line.id = CreateCRUID(Cast<Uint64>(885300 + n));
    line.text = text;
    if Equals(speaker, "V") {
      line.type = scnDialogLineType.Regular;
      line.speaker = GetPlayer(game);
    } else {
      line.type = scnDialogLineType.OwnerlessRegular;
    }
    line.speakerName = speaker;
    line.isPersistent = false;
    line.duration = seconds;
    let lines: array<scnDialogLineData>;
    ArrayPush(lines, line);
    board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
    let hide = new SlumlordHideLineCallback();
    hide.id = line.id;
    GameInstance.GetDelaySystem(game).DelayCallback(hide, seconds + 0.25, false);
  }

  private func HangUp() -> Void {
    this.m_callState = 0;
    this.m_watCallDone = true;
    this.m_watCallPending = false;
    this.SendCall(questPhoneCallPhase.EndCall);
    GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFactStr(SlumlordBoss.CallDoneFact(), 1);
    SlumlordUi.Log("Oshima call: done");
    let fight = SlumlordFight.GetInstance(this.GetGameInstance());
    if IsDefined(fight) {
      fight.CheckTrigger();
    }
  }

  public func IsCallDone() -> Bool {
    return this.m_watCallDone;
  }

  // What the phone HUD shows for our caller id.
  public func CallerName() -> String {
    return this.m_callState == 1 ? "Unknown" : "Hideyoshi Oshima";
  }

  public static func IsOurCall(game: GameInstance) -> Bool {
    let info = SlumlordBoss.CurrentCall(game);
    return Equals(info.contactName, SlumlordBoss.CallerId());
  }
}

public class SlumlordBossCallback extends DelayCallback {
  public let system: wref<SlumlordBoss>;
  public let action: CName;

  public func Call() -> Void {
    let sys = this.system;
    if IsDefined(sys) {
      sys.OnCallback(this.action);
    }
  }
}

// Subtitles shown through UIGameData.ShowDialogLine stay up until taken down again.
public class SlumlordHideLineCallback extends DelayCallback {
  public let id: CRUID;

  public func Call() -> Void {
    let board = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(board) { return; }
    let ids: array<CRUID>;
    ArrayPush(ids, this.id);
    board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(ids), true);
  }
}

// ---- hooks into the game's phone ----

@wrapMethod(PhoneSystem)
private final func SetPhoneFact(isPlayerCalling: Bool, contactName: CName, state: questPhoneTalkingState) -> Void {
  wrappedMethod(isPlayerCalling, contactName, state);
  if Equals(contactName, SlumlordBoss.CallerId()) {
    let boss = SlumlordBoss.GetInstance(this.GetGameInstance());
    if IsDefined(boss) {
      boss.OnPhoneState(state);
    }
  }
}

// The ringing screen: our caller is no journal contact, so its name would be blank.
@wrapMethod(IncomingCallLogicController)
public final func SetCallInfo(const contactName: script_ref<String>, contactEntry: wref<JournalContact>, journalMgr: wref<JournalManager>, isRejectable: Bool) -> Void {
  let game = GetGameInstance();
  if !IsDefined(contactEntry) && SlumlordBoss.IsOurCall(game) {
    let boss = SlumlordBoss.GetInstance(game);
    let name: String = IsDefined(boss) ? boss.CallerName() : "Unknown";
    wrappedMethod(name, contactEntry, journalMgr, isRejectable);
    return;
  }
  wrappedMethod(contactName, contactEntry, journalMgr, isRejectable);
}

// The in-call panel.
@wrapMethod(HoloAudioCallLogicController)
public final func StartAudiocall(avatarID: TweakDBID, const contactName: script_ref<String>, showAvatar: Bool) -> Void {
  let game = GetGameInstance();
  if SlumlordBoss.IsOurCall(game) {
    let boss = SlumlordBoss.GetInstance(game);
    let name: String = IsDefined(boss) ? boss.CallerName() : "Hideyoshi Oshima";
    wrappedMethod(avatarID, name, showAvatar);
    return;
  }
  wrappedMethod(avatarID, contactName, showAvatar);
}

@wrapMethod(HoloAudioCallLogicController)
public final func ShowIncomingContact(avatarID: TweakDBID, const contactName: script_ref<String>) -> Void {
  let game = GetGameInstance();
  if SlumlordBoss.IsOurCall(game) {
    let boss = SlumlordBoss.GetInstance(game);
    let name: String = IsDefined(boss) ? boss.CallerName() : "Unknown";
    wrappedMethod(avatarID, name);
    return;
  }
  wrappedMethod(avatarID, contactName);
}

@wrapMethod(HoloAudioCallLogicController)
public final func ShowEndCallContact(avatarID: TweakDBID, const contactName: script_ref<String>) -> Void {
  if SlumlordBoss.IsOurCall(GetGameInstance()) {
    wrappedMethod(avatarID, "Hideyoshi Oshima");
    return;
  }
  wrappedMethod(avatarID, contactName);
}
