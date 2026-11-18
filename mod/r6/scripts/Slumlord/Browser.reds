// Slumlord's own browser hook. No browser framework required.
//
// 1. Serving: any address starting with NETdir://slumlord.estate is built by SlumlordSite instead of
//    the journal. Every other address goes to the game (and to other mods' hooks) unchanged.
// 2. Listing: on the NETdir home page (NETdir://ncity.pub) Slumlord takes a slot in the page's own link
//    grid (see SlumlordPlaceLink below), one frame after the page spawns, and only while the address bar
//    shows the home page (Virtual Atelier and Virtual Car Dealer reuse the home page for their tabs).
//    When InkGUI (Night City Allies) rebuilds the home page, the link joins its grid instead
//    (InkGuiBridge.reds). When Browser Extension Framework is installed it owns the home page, so the
//    link comes from BrowserExtensionBridge.reds instead and this part is compiled out.
module Slumlord

@addField(BrowserController)
private let m_slumlordSite: ref<SlumlordSite>;

@addMethod(BrowserController)
public func GetSlumlordSite() -> ref<SlumlordSite> {
  if !IsDefined(this.m_slumlordSite) {
    this.m_slumlordSite = new SlumlordSite();
    this.m_slumlordSite.Init(this);
  }
  return this.m_slumlordSite;
}

// Public entry point for navigation from Slumlord pages (LoadWebPage itself is private).
@addMethod(BrowserController)
public func SlumlordLoad(address: String) -> Void {
  this.LoadWebPage(address);
}

@wrapMethod(BrowserController)
private final func LoadWebPage(const address: script_ref<String>) -> Void {
  let requested: String = Deref(address);
  if !StrBeginsWith(requested, SlumlordSite.BaseAddress()) {
    SlumlordUi.Log("Browser load: " + requested);
    wrappedMethod(address);
    return;
  }
  let area: Vector2 = inkWidgetRef.GetSize(this.m_pageContentRoot);
  SlumlordUi.Log("Serving " + requested + " (page area " + FloatToStringPrec(area.X, 0) + " x " + FloatToStringPrec(area.Y, 0) + ")");

  if IsDefined(this.m_webPageSpawnRequest) {
    this.m_webPageSpawnRequest.Cancel();
  }
  this.UnloadCurrentWebsite();
  // Forget the journal page, so returning to the same vanilla page afterwards reloads it.
  this.m_currentRequestedPage = null;
  inkTextRef.SetText(this.m_addressText, requested);

  let page: ref<inkCompoundWidget> = this.GetSlumlordSite().GetWebPage(requested);
  if IsDefined(page) {
    page.Reparent(inkWidgetRef.Get(this.m_pageContentRoot) as inkCompoundWidget);
    page.SetAnchor(inkEAnchor.Fill);
    this.m_currentPage = page;
  }
  inkWidgetRef.SetVisible(this.m_spinnerContentRoot, false);
}

// The link is added one frame later, through a queued event, so that every other mod's OnPageSpawned
// hook has finished first. Virtual Atelier and Virtual Car Dealer reuse the home page for their own
// tabs and rename the address bar (NETdir://atelier.pub, NETdir://cyber.car); the link is only added
// while the address bar still reads the home page.
public class SlumlordHomeLinkEvent extends Event {
  public let attempts: Int32;
}

@if(!ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserController)
protected cb func OnPageSpawned(widget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
  let result: Bool = wrappedMethod(widget, userData);
  if IsDefined(this.m_currentRequestedPage) && Equals(this.m_currentRequestedPage.GetAddress(), SlumlordSite.HomeAddress()) {
    this.QueueEvent(new SlumlordHomeLinkEvent());
  }
  return result;
}

@if(!ModuleExists("BrowserExtension.System"))
@addMethod(BrowserController)
protected cb func OnSlumlordHomeLinkEvent(evt: ref<SlumlordHomeLinkEvent>) -> Bool {
  let page: wref<inkCompoundWidget> = this.m_currentPage;
  if !IsDefined(page) { return false; }
  if !IsDefined(this.m_currentRequestedPage) || !Equals(this.m_currentRequestedPage.GetAddress(), SlumlordSite.HomeAddress()) {
    return false;
  }
  let shown: String = inkTextRef.GetText(this.m_addressText);
  if !Equals(shown, SlumlordSite.HomeAddress()) {
    SlumlordUi.Log("Home link skipped: address bar shows " + shown);
    return false;
  }
  let webPage = page.GetController() as WebPage;
  if !IsDefined(webPage) {
    SlumlordUi.Log("Home link skipped: home page has no WebPage controller");
    return false;
  }
  // InkGUI (shipped with Night City Allies) rebuilds the home page grid when it has sites to list,
  // hiding the rows SetSlot writes into. Then Slumlord joins InkGUI's grid instead (InkGuiBridge.reds).
  // Its rebuild runs from its own queued event, so wait a few frames for the grid to appear.
  if webPage.SlumlordInkGuiOwnsHome() {
    if webPage.SlumlordAddInkGuiLink() {
      SlumlordUi.Log("Home link added to the InkGUI grid");
      return false;
    }
    if evt.attempts < SlumlordSite.HomeLinkMaxAttempts() {
      let retry = new SlumlordHomeLinkEvent();
      retry.attempts = evt.attempts + 1;
      this.QueueEvent(retry);
      return false;
    }
    SlumlordUi.Log("InkGUI grid not found; using a vanilla slot");
  }
  let slot = webPage.SlumlordPlaceLink();
  SlumlordUi.Log("Home link placed in slot " + IntToString(slot));
  return false;
}

// Puts Slumlord into the home page's own link grid (TextLinkNN / ImageLinkNN), using the game's
// SetSlot, so clicks go through the game's link handling: WebPage.OnLinkCallback -> OnLinkPressed ->
// BrowserController.LoadWebPage, which Browser.reds serves. Script-built widgets on the home page do
// not receive mouse input (tested in game 2026-11-17).
// Takes the first empty slot; if every slot is used, takes the last one.
@if(!ModuleExists("BrowserExtension.System"))
@addMethod(WebPage)
public func SlumlordPlaceLink() -> Int32 {
  let name: String = SlumlordSite.ShortName();
  let address: String = SlumlordSite.BaseAddress();
  let atlas: ResRef = SlumlordSite.IconAtlas();
  let part: CName = SlumlordSite.IconPart();
  let last: Int32 = 0;
  let n: Int32 = 1;
  while n <= 60 {
    let textRef: inkTextRef = this.GetTextRef(this.GetRefName("TextLink", n));
    let imageRef: inkImageRef = this.GetImageRef(this.GetRefName("ImageLink", n));
    if !inkTextRef.IsValid(textRef) && !inkImageRef.IsValid(imageRef) {
      break;
    }
    if inkTextRef.IsValid(textRef) && inkTextRef.IsVisible(textRef) && Equals(inkTextRef.GetText(textRef), name) {
      return n;
    }
    let used: Bool = (inkTextRef.IsValid(textRef) && inkTextRef.IsVisible(textRef)) || (inkImageRef.IsValid(imageRef) && inkImageRef.IsVisible(imageRef));
    if !used {
      this.SetSlot(n, name, address, atlas, part);
      return n;
    }
    last = n;
    n += 1;
  }
  if last > 0 {
    this.SetSlot(last, name, address, atlas, part);
  }
  return last;
}

// Diagnostics: which start page this computer gives its browser (set per device by the game).
@wrapMethod(BrowserController)
public final func SetDefaultPage(const startingPage: script_ref<String>) -> Void {
  SlumlordUi.Log("Browser start page: " + Deref(startingPage));
  wrappedMethod(startingPage);
}
