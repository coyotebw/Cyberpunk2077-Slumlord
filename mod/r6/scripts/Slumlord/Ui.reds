// Widget helpers that implement the Slumlord UI Design System in ink.
// Design-system sizes are web px; Scale() converts them to browser-page ink units.
// Tune Scale() first if the portal looks too big or too small in game.
module Slumlord

public abstract class SlumlordUi {

  // ------------------------------------------------------------------ scale and fonts

  public static func Scale() -> Float { return 2.8; }

  public static func Px(px: Float) -> Float { return px * SlumlordUi.Scale(); }

  // Rajdhani ships with the game. Share Tech Mono (mono) and the kanji face are not in the game yet,
  // so mono text uses Rajdhani Medium and kanji accents are off until fonts ship via ArchiveXL.
  public static func Font() -> String { return "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"; }
  public static func KanjiEnabled() -> Bool { return false; }
  // State glyphs (◆ ■ ▲ □). Turn off if Rajdhani shows empty boxes for them in game.
  public static func GlyphsEnabled() -> Bool { return true; }

  // ------------------------------------------------------------------ type styles

  public static func Text(text: String, sizePx: Float, style: CName, color: HDRColor, upper: Bool) -> ref<inkText> {
    let t = new inkText();
    t.SetText(text);
    t.SetFontFamily(SlumlordUi.Font());
    t.SetFontStyle(style);
    t.SetFontSize(RoundF(SlumlordUi.Px(sizePx)));
    t.SetTintColor(color);
    if upper {
      t.SetLetterCase(textLetterCase.UpperCase);
    }
    t.SetFitToContent(true);
    return t;
  }

  public static func MoneyXL(text: String) -> ref<inkText> { return SlumlordUi.Text(text, 64.0, n"Bold", SlumlordColors.Gold(), false); }
  public static func Display(text: String) -> ref<inkText> { return SlumlordUi.Text(text, 40.0, n"Bold", SlumlordColors.Ink(), true); }
  public static func Title(text: String) -> ref<inkText> { return SlumlordUi.Text(text, 22.0, n"Bold", SlumlordColors.Ink(), true); }
  public static func Body(text: String, color: HDRColor) -> ref<inkText> { return SlumlordUi.Text(text, 16.0, n"Medium", color, false); }
  public static func ButtonLabel(text: String, color: HDRColor) -> ref<inkText> { return SlumlordUi.Text(text, 15.0, n"Bold", color, true); }
  public static func TagLabel(text: String, color: HDRColor) -> ref<inkText> { return SlumlordUi.Text(text, 13.0, n"Bold", color, true); }
  public static func Data(text: String, color: HDRColor) -> ref<inkText> { return SlumlordUi.Text(text, 15.0, n"Medium", color, false); }
  public static func Caption(text: String) -> ref<inkText> { return SlumlordUi.Text(text, 12.0, n"Medium", SlumlordColors.InkMuted(), true); }

  // Every stat is a caption over a value. No bare numbers.
  public static func Stat(caption: String, value: String, color: HDRColor) -> ref<inkVerticalPanel> {
    let col = new inkVerticalPanel();
    col.SetFitToContent(true);
    col.SetChildMargin(new inkMargin(0.0, 0.0, 0.0, SlumlordUi.Px(4.0)));
    SlumlordUi.Caption(caption).Reparent(col);
    SlumlordUi.Data(value, color).Reparent(col);
    return col;
  }

  public static func Row(gapPx: Float) -> ref<inkHorizontalPanel> {
    let row = new inkHorizontalPanel();
    row.SetFitToContent(true);
    row.SetChildMargin(new inkMargin(0.0, 0.0, SlumlordUi.Px(gapPx), 0.0));
    return row;
  }

  public static func Column(gapPx: Float) -> ref<inkVerticalPanel> {
    let col = new inkVerticalPanel();
    col.SetFitToContent(true);
    col.SetChildMargin(new inkMargin(0.0, 0.0, 0.0, SlumlordUi.Px(gapPx)));
    return col;
  }

  // ------------------------------------------------------------------ shapes

  public static func WithAlpha(color: HDRColor, alpha: Float) -> HDRColor {
    let c = color;
    c.Alpha = alpha;
    return c;
  }

  // Sizes here are already in ink units (use Px() to convert).
  public static func Rect(w: Float, h: Float, color: HDRColor) -> ref<inkRectangle> {
    let r = new inkRectangle();
    r.SetAnchor(inkEAnchor.TopLeft);
    r.SetSize(new Vector2(w, h));
    r.SetTintColor(color);
    return r;
  }

  // Panel: fill, 1px inset frame, and the top-right chamfer (design system `cut-*`).
  // The chamfer is drawn by covering the corner with a void diamond and laying a frame-coloured
  // diagonal across it. Sizes are in ink units; cut is in design px.
  public static func Panel(w: Float, h: Float, fill: HDRColor, frame: HDRColor, cutPx: Float) -> ref<inkCanvas> {
    let c = new inkCanvas();
    c.SetAnchor(inkEAnchor.TopLeft);
    c.SetSize(new Vector2(w, h));
    c.SetFitToContent(false);
    // Panels default to stretching inside vertical/horizontal panels, which moves centred text
    // away from the fixed-size shapes. Pin them to their own size.
    c.SetHAlign(inkEHorizontalAlign.Left);
    c.SetVAlign(inkEVerticalAlign.Top);
    SlumlordUi.Rect(w, h, fill).Reparent(c);
    let t = MaxF(SlumlordUi.Px(1.0), 2.0);
    SlumlordUi.Place(SlumlordUi.Rect(w, t, frame), 0.0, 0.0, c);
    SlumlordUi.Place(SlumlordUi.Rect(w, t, frame), 0.0, h - t, c);
    SlumlordUi.Place(SlumlordUi.Rect(t, h, frame), 0.0, 0.0, c);
    SlumlordUi.Place(SlumlordUi.Rect(t, h, frame), w - t, 0.0, c);
    if cutPx > 0.0 {
      SlumlordUi.Chamfer(c, w, SlumlordUi.Px(cutPx), t, frame);
    }
    return c;
  }

  // Positions a child inside a canvas by layout margin, not by render translation: the game decides what
  // was clicked from layout positions, so a translated button is drawn in one place and clicked in another.
  public static func Place(w: ref<inkWidget>, x: Float, y: Float, parent: ref<inkCompoundWidget>) -> Void {
    w.SetAnchor(inkEAnchor.TopLeft);
    w.SetMargin(new inkMargin(x, y, 0.0, 0.0));
    w.Reparent(parent);
  }

  // If the diagonal edge appears on the wrong diagonal in game, flip the sign of the edge rotation.
  private static func Chamfer(c: ref<inkCanvas>, w: Float, cut: Float, t: Float, frame: HDRColor) -> Void {
    let side = cut * 1.41421;
    let cover = SlumlordUi.Rect(side, side, SlumlordColors.VoidColor());
    cover.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    cover.SetRotation(45.0);
    SlumlordUi.Place(cover, w - side / 2.0, 0.0 - side / 2.0, c);
    let edge = SlumlordUi.Rect(side, t, frame);
    edge.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    edge.SetRotation(45.0);
    SlumlordUi.Place(edge, w - cut / 2.0 - side / 2.0, cut / 2.0 - t / 2.0, c);
  }

  // ------------------------------------------------------------------ components

  // Buttons. kind: n"gold" (Buy, Collect), n"outline" (chrome), n"ghost" (text only).
  // The caller registers OnRelease on the returned widget; its name identifies the action.
  public static func Button(label: String, name: CName, widthPx: Float, kind: CName, enabled: Bool) -> ref<inkCanvas> {
    let w = SlumlordUi.Px(widthPx);
    let h = SlumlordUi.Px(36.0);
    let fill: HDRColor;
    let hoverFill: HDRColor;
    let frame: HDRColor;
    let textColor: HDRColor;
    if Equals(kind, n"gold") {
      fill = SlumlordColors.Gold();
      hoverFill = SlumlordColors.GoldBright();
      frame = SlumlordColors.Gold();
      textColor = SlumlordColors.OnGold();
    } else {
      if Equals(kind, n"outline") {
        fill = SlumlordUi.WithAlpha(SlumlordColors.ChromeDim(), 0.0);
        hoverFill = SlumlordColors.ChromeDim();
        frame = SlumlordColors.Chrome();
        textColor = SlumlordColors.Chrome();
      } else {
        fill = SlumlordUi.WithAlpha(SlumlordColors.Panel(), 0.0);
        hoverFill = SlumlordColors.PanelRaised();
        frame = SlumlordUi.WithAlpha(SlumlordColors.Panel(), 0.0);
        textColor = SlumlordColors.InkMuted();
      }
    }

    let root = new inkCanvas();
    root.SetName(name);
    root.SetAnchor(inkEAnchor.TopLeft);
    root.SetSize(new Vector2(w, h));
    root.SetFitToContent(false);
    root.SetHAlign(inkEHorizontalAlign.Left);
    root.SetVAlign(inkEVerticalAlign.Top);

    // The background rectangle is the click target. It is the first child, and it carries the
    // button's name, so handlers read evt.GetCurrentTarget().GetName() as before.
    let bg = SlumlordUi.Rect(w, h, fill);
    bg.SetName(name);
    bg.Reparent(root);
    let t = MaxF(SlumlordUi.Px(1.0), 2.0);
    SlumlordUi.Place(SlumlordUi.Rect(w, t, frame), 0.0, 0.0, root);
    SlumlordUi.Place(SlumlordUi.Rect(w, t, frame), 0.0, h - t, root);
    SlumlordUi.Place(SlumlordUi.Rect(t, h, frame), 0.0, 0.0, root);
    SlumlordUi.Place(SlumlordUi.Rect(t, h, frame), w - t, 0.0, root);
    SlumlordUi.Chamfer(root, w, SlumlordUi.Px(8.0), t, frame);

    let text = SlumlordUi.ButtonLabel(label, textColor);
    text.SetAnchor(inkEAnchor.Centered);
    text.SetAnchorPoint(new Vector2(0.5, 0.5));
    text.Reparent(root);

    if enabled {
      bg.SetInteractive(true);
      let ctrl = new SlumlordButtonController();
      ctrl.bg = bg;
      ctrl.normalFill = fill;
      ctrl.hoverFill = hoverFill;
      bg.AttachController(ctrl);
    } else {
      root.SetInteractive(false);
      root.SetOpacity(0.4);
    }
    return root;
  }

  // Registers a click handler on a Button. Use this instead of RegisterToCallback on the button itself:
  // the click lands on the button's background rectangle, not on its container.
  public static func OnClick(button: ref<inkCanvas>, target: ref<IScriptable>, handler: CName) -> Void {
    let hit = button.GetWidgetByIndex(0);
    if IsDefined(hit) {
      hit.RegisterToCallback(n"OnRelease", target, handler);
    }
  }

  // Development logging, written to Cyber Engine Tweaks' gamelog.log. Off for release builds.
  public static func DebugLog() -> Bool { return true; }

  public static func Log(text: String) -> Void {
    if SlumlordUi.DebugLog() {
      ModLog(n"Slumlord", text);
    }
  }

  // Status tag: one or two words. kind: n"rent", n"secured", n"vacant", n"trouble", n"dominated".
  public static func Tag(label: String, kind: CName) -> ref<inkCanvas> {
    let fill: HDRColor;
    let frame: HDRColor;
    let textColor: HDRColor;
    let prefix = "";
    if Equals(kind, n"rent") || Equals(kind, n"dominated") {
      fill = SlumlordColors.GoldDim(); frame = SlumlordColors.GoldDim(); textColor = SlumlordColors.Gold(); prefix = "◆ ";
    } else {
      if Equals(kind, n"secured") {
        fill = SlumlordColors.CyanDim(); frame = SlumlordColors.CyanDim(); textColor = SlumlordColors.Cyan(); prefix = "■ ";
      } else {
        if Equals(kind, n"trouble") {
          fill = SlumlordColors.Trouble(); frame = SlumlordColors.Trouble(); textColor = SlumlordColors.OnTrouble(); prefix = "▲ ";
        } else {
          fill = SlumlordUi.WithAlpha(SlumlordColors.Panel(), 0.0); frame = SlumlordColors.LineStrong(); textColor = SlumlordColors.InkMuted(); prefix = "□ ";
        }
      }
    }
    let w = SlumlordUi.Px(12.0 + 8.0 * Cast<Float>(StrLen(label) + 2));
    let h = SlumlordUi.Px(24.0);
    let tag = SlumlordUi.Panel(w, h, fill, frame, 0.0);
    if !SlumlordUi.GlyphsEnabled() { prefix = ""; }
    let text = SlumlordUi.TagLabel(prefix + label, textColor);
    text.SetAnchor(inkEAnchor.Centered);
    text.SetAnchorPoint(new Vector2(0.5, 0.5));
    text.Reparent(tag);
    return tag;
  }

  // Rank letter in its rank colour inside a small framed square.
  public static func RankBadge(rank: Int32) -> ref<inkCanvas> {
    let size = SlumlordUi.Px(36.0);
    let color = SlumlordColors.ForRank(rank);
    let fill = rank == SlumlordTuning.MaxRank() ? SlumlordColors.GoldDim() : SlumlordColors.PanelRaised();
    let badge = SlumlordUi.Panel(size, size, fill, color, 8.0);
    let letter = SlumlordUi.Text(SlumlordEconomy.RankLetter(rank), 24.0, n"Bold", color, false);
    letter.SetAnchor(inkEAnchor.Centered);
    letter.SetAnchorPoint(new Vector2(0.5, 0.5));
    letter.Reparent(badge);
    return badge;
  }

  // District control: one segment per property, gold when owned.
  public static func ControlMeter(owned: Int32, total: Int32) -> ref<inkHorizontalPanel> {
    let row = SlumlordUi.Row(4.0);
    let i = 0;
    while i < total {
      let color = i < owned ? SlumlordColors.Gold() : SlumlordColors.Line();
      SlumlordUi.Rect(SlumlordUi.Px(28.0), SlumlordUi.Px(8.0), color).Reparent(row);
      i += 1;
    }
    return row;
  }

  // ------------------------------------------------------------------ sound

  public static func PlaySound(sound: CName) -> Void {
    let player = GetPlayer(GetGameInstance());
    if !IsDefined(player) { return; }
    let evt = new AudioEvent();
    evt.eventName = sound;
    player.QueueEvent(evt);
  }
}

// Hover state for buttons: gold goes gold-bright, outline fills chrome-dim, ghost raises.
public class SlumlordButtonController extends inkLogicController {
  public let bg: wref<inkRectangle>;
  public let normalFill: HDRColor;
  public let hoverFill: HDRColor;

  protected cb func OnInitialize() -> Bool {
    this.RegisterToCallback(n"OnEnter", this, n"OnEnterCb");
    this.RegisterToCallback(n"OnLeave", this, n"OnLeaveCb");
    this.RegisterToCallback(n"OnRelease", this, n"OnReleaseCb");
    return true;
  }

  protected cb func OnReleaseCb(evt: ref<inkPointerEvent>) -> Bool {
    SlumlordUi.Log("Click reached button " + NameToString(this.GetRootWidget().GetName()));
    return false;
  }

  private let loggedHover: Bool;

  protected cb func OnEnterCb(evt: ref<inkPointerEvent>) -> Bool {
    if !this.loggedHover {
      this.loggedHover = true;
      SlumlordUi.Log("Hover reached button " + NameToString(this.GetRootWidget().GetName()));
    }
    if IsDefined(this.bg) { this.bg.SetTintColor(this.hoverFill); }
    SlumlordUi.PlaySound(n"ui_menu_hover");
    return false;
  }

  protected cb func OnLeaveCb(evt: ref<inkPointerEvent>) -> Bool {
    if IsDefined(this.bg) { this.bg.SetTintColor(this.normalFill); }
    return false;
  }
}
