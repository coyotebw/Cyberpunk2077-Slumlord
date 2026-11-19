// Boss phone calls (design doc 4.8, 4.9), one at a time, in this order when several are waiting:
//   n"wat_oshima"  Oshima, after V's first Watson purchase (Million Dollar Baby starts when it ends)
//   n"sd_threat"   Quentin Finger's threat, after V's first Santo Domingo purchase (Conversation Overtime starts)
//   n"sd_goad"     Finger's goading call, once V owns all of Santo Domingo (Finger.reds asks for it)
//
// Built on the game's own phone. PhoneSystem rings V with a caller id that is not a phone contact
// (no journal entry needed), so the phone HUD shows a blank name and the "unknown" avatar; the wraps at
// the bottom fill in the caller's name. PhoneSystem reports pickup through SetPhoneFact
// (phonecall_<caller>_with_player = questPhoneTalkingState).
// Voice: Audioware sfx (r6/audioware/Slumlord/slumlord.yml), played 2D; a line with no audio name is
// subtitle-only (Finger until Andrew records him). Subtitles through the UIGameData.ShowDialogLine
// blackboard (the same pattern as Cerberus Ride).
module Slumlord

public class SlumlordBoss extends ScriptableSystem {
  private persistent let m_watCallPending: Bool;   // first Watson property bought, call not taken yet
  private persistent let m_watCallDone: Bool;      // Oshima's call finished
  private persistent let m_sdThreatPending: Bool;
  private persistent let m_sdThreatDone: Bool;     // Finger's threat finished: V has met him
  private persistent let m_sdGoadPending: Bool;
  private persistent let m_sdGoadDone: Bool;

  private let m_callState: Int32;                  // 0 idle, 1 ringing, 2 talking
  private let m_active: CName;                     // the call ringing or in progress
  private let m_lastCaller: String;                // shown on the end-of-call screen
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
  public static func FingerCallDoneFact() -> String { return "slumlord_sd_call_done"; }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_callState = 0;
    this.m_active = n"";
    this.m_attemptQueued = false;
    if IsNameValid(this.NextPending()) {
      this.ScheduleAttempt(60.0);
    }
  }

  // ---- triggers ----

  public func OnPropertyBought(def: ref<SlumlordPropertyDef>) -> Void {
    if !IsDefined(def) { return; }
    if Equals(def.districtId, n"watson") && !this.m_watCallDone && !this.m_watCallPending {
      this.m_watCallPending = true;
      SlumlordUi.Log("Boss calls: first Watson purchase, Oshima rings in " + FloatToStringPrec(SlumlordBoss.CallDelaySeconds(), 0) + " s");
      this.ScheduleAttempt(SlumlordBoss.CallDelaySeconds());
    }
    if Equals(def.districtId, n"santo_domingo") && !this.m_sdThreatDone && !this.m_sdThreatPending {
      this.m_sdThreatPending = true;
      SlumlordUi.Log("Boss calls: first Santo Domingo purchase, Finger rings in " + FloatToStringPrec(SlumlordBoss.CallDelaySeconds(), 0) + " s");
      this.ScheduleAttempt(SlumlordBoss.CallDelaySeconds());
    }
  }

  // Finger.reds: V owns all of Santo Domingo.
  public func RequestFingerGoad(delay: Float) -> Void {
    if this.m_sdGoadDone || this.m_sdGoadPending { return; }
    this.m_sdGoadPending = true;
    this.ScheduleAttempt(delay);
  }

  private func NextPending() -> CName {
    if this.m_watCallPending && !this.m_watCallDone { return n"wat_oshima"; }
    if this.m_sdThreatPending && !this.m_sdThreatDone { return n"sd_threat"; }
    if this.m_sdGoadPending && !this.m_sdGoadDone { return n"sd_goad"; }
    return n"";
  }

  public func Debug_RingNow() -> Void {
    this.m_watCallDone = false;
    this.m_watCallPending = true;
    this.m_callState = 0;
    this.TryRing();
  }

  public func Debug_RingFinger(goad: Bool) -> Void {
    if goad {
      this.m_sdGoadDone = false;
      this.m_sdGoadPending = true;
    } else {
      this.m_sdThreatDone = false;
      this.m_sdThreatPending = true;
    }
    this.m_callState = 0;
    this.TryRing();
  }

  public func Debug_Reset() -> Void {
    this.m_watCallDone = false;
    this.m_watCallPending = false;
    this.m_callState = 0;
    GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFactStr(SlumlordBoss.CallDoneFact(), 0);
  }

  public func Debug_ResetFinger() -> Void {
    this.m_sdThreatPending = false;
    this.m_sdThreatDone = false;
    this.m_sdGoadPending = false;
    this.m_sdGoadDone = false;
    this.m_callState = 0;
    GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFactStr(SlumlordBoss.FingerCallDoneFact(), 0);
  }

  public func Debug_State() -> String {
    return "oshima pending=" + (this.m_watCallPending ? "yes" : "no") + " done=" + (this.m_watCallDone ? "yes" : "no")
      + " | finger threat " + (this.m_sdThreatDone ? "done" : (this.m_sdThreatPending ? "pending" : "-"))
      + " goad " + (this.m_sdGoadDone ? "done" : (this.m_sdGoadPending ? "pending" : "-"))
      + " | state=" + IntToString(this.m_callState) + " active=" + NameToString(this.m_active);
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
    if this.m_callState != 0 { return; }
    let next = this.NextPending();
    if !IsNameValid(next) { return; }
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) || player.IsInCombat() || this.OtherCallActive() {
      this.ScheduleAttempt(SlumlordBoss.RetrySeconds());
      return;
    }
    this.m_active = next;
    this.m_callState = 1;
    this.SendCall(questPhoneCallPhase.IncomingCall);
    SlumlordUi.Log("Boss calls: ringing " + NameToString(next));
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
      SlumlordUi.Log("Boss calls: picked up " + NameToString(this.m_active));
      this.SendCall(questPhoneCallPhase.StartCall);
      this.Queue(n"line", 0.8);
      return;
    }
    if this.m_callState == 1 && (Equals(state, questPhoneTalkingState.Ended) || Equals(state, questPhoneTalkingState.Rejected)) {
      this.m_callState = 0;
      this.m_active = n"";
      SlumlordUi.Log("Boss calls: missed, calling again later");
      this.ScheduleAttempt(SlumlordBoss.MissedRetrySeconds());
    }
  }

  // ---- the conversations ----

  private func PlayNextLine() -> Void {
    if this.m_callState != 2 { return; }
    let n = this.m_line;
    this.m_line += 1;
    let player = GetPlayer(this.GetGameInstance());
    let male = IsDefined(player) && Equals(player.GetResolvedGenderName(), n"Male");
    let line = new SlumlordCallLine();
    let found = false;
    if Equals(this.m_active, n"wat_oshima") { found = SlumlordCallScripts.Oshima(n, male, line); }
    if Equals(this.m_active, n"sd_threat") { found = SlumlordCallScripts.FingerThreat(n, male, line); }
    if Equals(this.m_active, n"sd_goad") { found = SlumlordCallScripts.FingerGoad(n, male, line); }
    if !found {
      this.Queue(n"hangup", 0.2);
      return;
    }
    this.Say(line, n);
    this.Queue(n"line", line.seconds + line.gap);
  }

  private func Say(line: ref<SlumlordCallLine>, n: Int32) -> Void {
    let game = this.GetGameInstance();
    if IsNameValid(line.audio) {
      GameInstance.GetAudioSystem(game).Play(line.audio);
    }
    let board = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
    if !IsDefined(board) { return; }
    // The subtitle HUD drops a Regular line without a speaker object (IsMainDialogLine): V's line is
    // spoken by V's puppet; the caller is not in the world, so their lines are OwnerlessRegular.
    let data: scnDialogLineData;
    data.id = CreateCRUID(Cast<Uint64>(885300 + n));
    data.text = line.text;
    if Equals(line.speaker, "V") {
      data.type = scnDialogLineType.Regular;
      data.speaker = GetPlayer(game);
    } else {
      data.type = scnDialogLineType.OwnerlessRegular;
    }
    data.speakerName = line.speaker;
    data.isPersistent = false;
    data.duration = line.seconds;
    let lines: array<scnDialogLineData>;
    ArrayPush(lines, data);
    board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
    let hide = new SlumlordHideLineCallback();
    hide.id = data.id;
    GameInstance.GetDelaySystem(game).DelayCallback(hide, line.seconds + 0.25, false);
  }

  private func HangUp() -> Void {
    let game = this.GetGameInstance();
    let finished = this.m_active;
    this.m_lastCaller = this.CallerName();
    this.m_callState = 0;
    this.m_active = n"";
    this.SendCall(questPhoneCallPhase.EndCall);
    SlumlordUi.Log("Boss calls: done " + NameToString(finished));
    if Equals(finished, n"wat_oshima") {
      this.m_watCallDone = true;
      this.m_watCallPending = false;
      GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordBoss.CallDoneFact(), 1);
      let fight = SlumlordFight.GetInstance(game);
      if IsDefined(fight) {
        fight.OnCallDone();
      }
    }
    if Equals(finished, n"sd_threat") {
      this.m_sdThreatDone = true;
      this.m_sdThreatPending = false;
      GameInstance.GetQuestsSystem(game).SetFactStr(SlumlordBoss.FingerCallDoneFact(), 1);
      let finger = SlumlordFinger.GetInstance(game);
      if IsDefined(finger) {
        finger.OnThreatCallDone();
      }
    }
    if Equals(finished, n"sd_goad") {
      this.m_sdGoadDone = true;
      this.m_sdGoadPending = false;
      let finger2 = SlumlordFinger.GetInstance(game);
      if IsDefined(finger2) {
        finger2.OnGoadCallDone();
      }
    }
    // Another call may be waiting (e.g. both districts bought in one sitting).
    if IsNameValid(this.NextPending()) {
      this.ScheduleAttempt(SlumlordBoss.MissedRetrySeconds());
    }
  }

  public func IsCallDone() -> Bool {
    return this.m_watCallDone;
  }

  public func IsFingerMet() -> Bool {
    return this.m_sdThreatDone;
  }

  public func IsFingerGoadDone() -> Bool {
    return this.m_sdGoadDone;
  }

  // What the phone HUD shows for our caller id: "Unknown" while a first call rings, the name after.
  public func CallerName() -> String {
    if !IsNameValid(this.m_active) && StrLen(this.m_lastCaller) > 0 {
      return this.m_lastCaller;
    }
    if Equals(this.m_active, n"sd_threat") {
      return this.m_callState == 1 ? "Unknown" : "Quentin Finger";
    }
    if Equals(this.m_active, n"sd_goad") {
      return "Quentin Finger";
    }
    return this.m_callState == 1 ? "Unknown" : "Hideyoshi Oshima";
  }

  public static func IsOurCall(game: GameInstance) -> Bool {
    let info = SlumlordBoss.CurrentCall(game);
    return Equals(info.contactName, SlumlordBoss.CallerId());
  }
}

// One line of a boss call. seconds: how long it stays up (audio length, or a reading estimate).
public class SlumlordCallLine {
  public let audio: CName;     // Audioware sfx name; n"" = subtitle only
  public let text: String;
  public let seconds: Float;
  public let speaker: String;
  public let gap: Float;

  public func Set(audio: CName, text: String, seconds: Float, speaker: String, gap: Float) -> Void {
    this.audio = audio;
    this.text = text;
    this.speaker = speaker;
    this.gap = gap;
    this.seconds = seconds > 0.0 ? seconds : SlumlordCallLine.ReadingTime(text);
  }

  // Subtitle-only lines: about 15 characters a second, at least 2 s.
  public static func ReadingTime(text: String) -> Float {
    return MaxF(2.0, 0.8 + Cast<Float>(StrLen(text)) / 15.0);
  }
}

// The scripts. Return false past the last line.
public abstract class SlumlordCallScripts {

  public static func Oshima(n: Int32, male: Bool, line: ref<SlumlordCallLine>) -> Bool {
    switch n {
      case 0: line.Set(n"slumlord_oshima_call_01", "V. Hideyoshi Oshima. I hear you've been buying up my locations.", 7.16, "Oshima", 0.9); return true;
      case 1: line.Set(n"slumlord_oshima_call_02", "Those buildings are sets for my braindances. Real damp, real despair. You can't build that in a studio. You're ruining the light.", 12.78, "Oshima", 0.9); return true;
      case 2: line.Set(n"slumlord_oshima_call_03", "So, an offer. I'll toss you five hundred eddies. Give up collecting rent and go back to shooting people.", 9.71, "Oshima", 0.6); return true;
      case 3: line.Set(male ? n"slumlord_v_call_01_m" : n"slumlord_v_call_01_f", "No.", male ? 1.23 : 0.96, "V", 0.6); return true;
      case 4: line.Set(n"slumlord_oshima_call_04", "Hmph. Big mistake. I'll be seeing you, V.", 4.61, "Oshima", 0.9); return true;
      default: return false;
    }
  }

  // Finger: Andrew's recordings (threat call, 2026-11-19). V: vanilla V lines (q307, q110, mq306), both voices.
  public static func FingerThreat(n: Int32, male: Bool, line: ref<SlumlordCallLine>) -> Bool {
    switch n {
      case 0: line.Set(n"slumlord_finger_call_01", "This the new landlord? The one buyin' up Santo?", 3.43, "Finger", 0.6); return true;
      case 1: line.Set(male ? n"slumlord_v_sdcall_01_m" : n"slumlord_v_sdcall_01_f", "And you are?", male ? 1.03 : 1.26, "V", 0.6); return true;
      case 2: line.Set(n"slumlord_finger_call_02", "Name's Quentin Finger. Owner of the Las Palapas? Been runnin' Arroyo since before your balls dropped, squirt.", 7.04, "Finger", 0.6); return true;
      case 3: line.Set(male ? n"slumlord_v_sdcall_02_m" : n"slumlord_v_sdcall_02_f", "Right.", male ? 0.88 : 0.89, "V", 0.6); return true;
      case 4: line.Set(n"slumlord_finger_call_03", "Santo's got one landlord. Me. You wanna flip apartments, go do it in Watson with the rest of the gonks.", 7.42, "Finger", 0.6); return true;
      case 5: line.Set(n"slumlord_finger_call_04", "Here's how it goes. Sell off what you bought, stay the fuck out of my neighborhood, and nobody gets hurt. You don't, and your tenants start havin' a real bad time. Then maybe you do, too.", 12.17, "Finger", 0.6); return true;
      case 6: line.Set(male ? n"slumlord_v_sdcall_03_m" : n"slumlord_v_sdcall_03_f", "Fuck you and your offer.", male ? 1.65 : 1.61, "V", 0.6); return true;
      // Second sentence to someone in the background (record turned away from the mic).
      case 7: line.Set(n"slumlord_finger_call_05", "Alright, asshole. Be seein' ya. Hey, Paulie, get the jumper cables.", 5.65, "Finger", 0.9); return true;
      default: return false;
    }
  }

  public static func FingerGoad(n: Int32, male: Bool, line: ref<SlumlordCallLine>) -> Bool {
    switch n {
      case 0: line.Set(n"", "Hey, shithead. I stole somethin' of yours.", 0.0, "Finger", 0.6); return true;
      case 1: line.Set(n"", "Want it back? Las Palapas. Tonight. Come alone.", 0.0, "Finger", 0.9); return true;
      default: return false;
    }
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
  let game = GetGameInstance();
  if SlumlordBoss.IsOurCall(game) {
    let boss = SlumlordBoss.GetInstance(game);
    let name: String = IsDefined(boss) ? boss.CallerName() : "Unknown";
    wrappedMethod(avatarID, name);
    return;
  }
  wrappedMethod(avatarID, contactName);
}
