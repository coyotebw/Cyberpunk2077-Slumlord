// Dev tool: noclip flight for scouting property and scene positions. Toggled from the CET tool
// (button or the "Toggle noclip" hotkey). Flies along the camera: move keys / stick, Jump up,
// Crouch down, Sprint for speed. V is invulnerable while flying and for 10 s after.
// Each frame V is teleported to a position this system integrates, so collision and gravity don't apply.
// Frames are driven by the CET tool's onUpdate (Step); input comes from listeners on the player:
// the MoveX/MoveY axes, with the Forward/Back/Left/Right buttons as a fallback. Status() reports what
// arrived, for the CET window.
module Slumlord

public class SlumlordNoclip extends ScriptableSystem {
  private let m_on: Bool;
  private let m_god: Bool;            // our god mode is on: added once, removed once (a second add leaked it, 2026-11-20)
  private let m_pos: Vector4;
  private let m_x: Float;
  private let m_y: Float;
  private let m_up: Bool;
  private let m_down: Bool;
  private let m_fast: Bool;
  private let m_listening: Bool;
  private let m_generation: Int32;   // stale callbacks from an earlier toggle stop themselves
  private let m_fwdBtn: Float;        // button fallback: +1/-1 while held
  private let m_rightBtn: Float;
  private let m_frames: Int32;
  private let m_lastAction: CName;

  public static func GetInstance(game: GameInstance) -> ref<SlumlordNoclip> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"Slumlord.SlumlordNoclip") as SlumlordNoclip;
  }

  public static func Speed() -> Float { return 8.0; }
  public static func FastSpeed() -> Float { return 30.0; }
  public static func GraceSeconds() -> Float { return 10.0; }
  public static func Source() -> CName { return n"SlumlordNoclip"; }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.m_on = false;
    this.m_listening = false;
    this.m_god = true;
    this.SetGod(false);   // clear anything left from before
  }

  private func SetGod(on: Bool) -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) || Equals(on, this.m_god) { return; }
    let gods = GameInstance.GetGodModeSystem(this.GetGameInstance());
    if on {
      gods.AddGodMode(player.GetEntityID(), gameGodModeType.Invulnerable, SlumlordNoclip.Source());
    } else {
      // Remove every entry with our source (older builds could add it twice).
      let n = 0;
      while n < 8 {
        gods.RemoveGodMode(player.GetEntityID(), gameGodModeType.Invulnerable, SlumlordNoclip.Source());
        n += 1;
      }
    }
    this.m_god = on;
  }

  public func IsOn() -> Bool {
    return this.m_on;
  }

  public func Toggle() -> Bool {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) { return this.m_on; }
    this.m_generation += 1;
    if !this.m_on {
      this.m_on = true;
      this.m_pos = player.GetWorldPosition();
      this.m_x = 0.0;
      this.m_y = 0.0;
      this.m_up = false;
      this.m_down = false;
      this.m_fast = false;
      this.m_fwdBtn = 0.0;
      this.m_rightBtn = 0.0;
      this.m_frames = 0;
      this.m_lastAction = n"";
      this.SetGod(true);
      if !this.m_listening {
        player.RegisterInputListener(this, n"MoveX");
        player.RegisterInputListener(this, n"MoveY");
        player.RegisterInputListener(this, n"Forward");
        player.RegisterInputListener(this, n"Back");
        player.RegisterInputListener(this, n"Left");
        player.RegisterInputListener(this, n"Right");
        player.RegisterInputListener(this, n"Jump");
        player.RegisterInputListener(this, n"Crouch");
        player.RegisterInputListener(this, n"ToggleCrouch");
        player.RegisterInputListener(this, n"Sprint");
        player.RegisterInputListener(this, n"ToggleSprint");
        this.m_listening = true;
      }
      SlumlordUi.Log("Noclip on");
    } else {
      this.m_on = false;
      let cb = new SlumlordNoclipCallback();
      cb.system = this;
      cb.generation = this.m_generation;
      GameInstance.GetDelaySystem(game).DelayCallback(cb, SlumlordNoclip.GraceSeconds(), false);
      SlumlordUi.Log("Noclip off");
    }
    return this.m_on;
  }

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    if !this.m_on { return false; }
    let name = ListenerAction.GetName(action);
    this.m_lastAction = name;
    if Equals(name, n"Forward") {
      this.m_fwdBtn = SlumlordNoclip.Button(action, this.m_fwdBtn, 1.0);
    } else if Equals(name, n"Back") {
      this.m_fwdBtn = SlumlordNoclip.Button(action, this.m_fwdBtn, -1.0);
    } else if Equals(name, n"Right") {
      this.m_rightBtn = SlumlordNoclip.Button(action, this.m_rightBtn, 1.0);
    } else if Equals(name, n"Left") {
      this.m_rightBtn = SlumlordNoclip.Button(action, this.m_rightBtn, -1.0);
    } else if Equals(name, n"MoveX") {
      this.m_x = ListenerAction.GetValue(action);
    } else if Equals(name, n"MoveY") {
      this.m_y = ListenerAction.GetValue(action);
    } else if Equals(name, n"Jump") {
      this.m_up = SlumlordNoclip.Held(action, this.m_up);
    } else if Equals(name, n"Crouch") || Equals(name, n"ToggleCrouch") {
      this.m_down = SlumlordNoclip.Held(action, this.m_down);
    } else if Equals(name, n"Sprint") || Equals(name, n"ToggleSprint") {
      this.m_fast = SlumlordNoclip.Held(action, this.m_fast);
    }
    return false;
  }

  // A direction button: pressed sets its sign, releasing clears it only if it is still the active one.
  private static func Button(action: ListenerAction, current: Float, sign: Float) -> Float {
    if ListenerAction.IsButtonJustPressed(action) { return sign; }
    if ListenerAction.IsButtonJustReleased(action) && current == sign { return 0.0; }
    return current;
  }

  private static func Held(action: ListenerAction, current: Bool) -> Bool {
    if ListenerAction.IsButtonJustPressed(action) { return true; }
    if ListenerAction.IsButtonJustReleased(action) { return false; }
    return current;
  }

  // Called every frame by the CET tool while noclip is on.
  public func Step(dt: Float) -> Void {
    if !this.m_on { return; }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      this.m_on = false;
      return;
    }
    this.m_frames += 1;
    dt = ClampF(dt, 0.0, 0.1);
    let fwd = AbsF(this.m_y) > 0.05 ? this.m_y : this.m_fwdBtn;
    let side = AbsF(this.m_x) > 0.05 ? this.m_x : this.m_rightBtn;
    let camera = GameInstance.GetCameraSystem(game);
    let move = camera.GetActiveCameraForward() * fwd + camera.GetActiveCameraRight() * side;
    if this.m_up { move.Z += 1.0; }
    if this.m_down { move.Z -= 1.0; }
    move.W = 0.0;
    let speed = this.m_fast ? SlumlordNoclip.FastSpeed() : SlumlordNoclip.Speed();
    this.m_pos = this.m_pos + move * (speed * dt);
    this.m_pos.W = 1.0;
    let angles: EulerAngles;
    angles.Yaw = player.GetWorldYaw();
    GameInstance.GetTeleportationFacility(game).Teleport(player, this.m_pos, angles);
  }

  public func Status() -> String {
    if !this.m_on { return "off"; }
    return "on, frames " + IntToString(this.m_frames) + ", move " + FloatToStringPrec(this.m_y, 1) + "/" + FloatToStringPrec(this.m_x, 1)
      + " buttons " + FloatToStringPrec(this.m_fwdBtn, 0) + "/" + FloatToStringPrec(this.m_rightBtn, 0)
      + (this.m_up ? " up" : "") + (this.m_down ? " down" : "") + (this.m_fast ? " fast" : "")
      + ", last input " + NameToString(this.m_lastAction);
  }

  public func OnGraceOver(generation: Int32) -> Void {
    if this.m_on || generation != this.m_generation { return; }
    this.SetGod(false);
  }
}

public class SlumlordNoclipCallback extends DelayCallback {
  public let system: wref<SlumlordNoclip>;
  public let generation: Int32;

  public func Call() -> Void {
    let sys = this.system;
    if !IsDefined(sys) { return; }
    sys.OnGraceOver(this.generation);
  }
}
