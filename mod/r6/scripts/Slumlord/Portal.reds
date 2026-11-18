// The Slumlord portal: a NETdir site on every in-game computer.
// Address: NETdir://slumlord.estate  Pages: /listings /holdings /districts /collect /renovate
// Filters: ?d=<district id> (listings, holdings), ?p=<property id> (renovate)
// Layout follows the Slumlord UI Design System. Sizes are design px, converted by SlumlordUi.Px().
// Hooked into the browser by Browser.reds (no framework needed); also registers with Browser Extension
// when that is installed (BrowserExtensionBridge.reds).
module Slumlord

public class SlumlordSite extends IScriptable {
  private let m_browser: wref<BrowserController>;
  private let m_base: String;
  private let m_currentAddress: String;
  private let m_message: String;
  private let m_messageKind: CName;   // n"good", n"bad"
  private let m_lastCollected: Int32;
  private let m_renovateProperty: CName;   // property on the Renovate page

  // Scrolling: the body is a list of rows; the mouse wheel hides rows from the top.
  private let m_rows: array<wref<inkWidget>>;
  private let m_scrollIndex: Int32;
  private let m_scrollPage: CName;
  private let m_scrollHint: wref<inkText>;

  // Card sizes in design px.
  private let m_cardW: Float;
  private let m_cardH: Float;
  private let m_holdingCardH: Float;
  private let m_contractorCardH: Float;
  private let m_districtCardW: Float;
  private let m_districtCardH: Float;

  public static func BaseAddress() -> String { return "NETdir://slumlord.estate"; }
  public static func HomeAddress() -> String { return "NETdir://ncity.pub"; }
  public static func ShortName() -> String { return "Slumlord Realty"; }
  // Home page icon: the seal and wordmark, from Slumlord.archive (art/slumlord_home@2x.png, tools/icon).
  public static func IconAtlas() -> ResRef { return r"slumlord\\gui\\slumlord_icons.inkatlas"; }
  public static func IconPart() -> CName { return n"slumlord_home"; }
  // Frames to wait for another mod's home page rebuild before falling back to a vanilla slot.
  public static func HomeLinkMaxAttempts() -> Int32 { return 10; }

  public func Init(browser: wref<BrowserController>) -> Void {
    this.m_browser = browser;
    this.m_base = SlumlordSite.BaseAddress();
    // Sized for SlumlordUi.Scale() 2.8 on the browser page (about 1,120 x 440 design px visible):
    // four property cards or three district cards to a row; the wheel scrolls row by row.
    this.m_cardW = 220.0;
    this.m_cardH = 250.0;
    this.m_holdingCardH = 262.0;     // room for the Renovate button
    this.m_contractorCardH = 236.0;  // a row of four fits under the Renovate summary strip
    this.m_districtCardW = 280.0;
    this.m_districtCardH = 136.0;
  }

  private func Sys() -> ref<SlumlordSystem> {
    return SlumlordSystem.GetInstance(GetGameInstance());
  }

  // ================================================================== page entry

  public func GetWebPage(address: String) -> ref<inkCompoundWidget> {
    SlumlordUi.Log("Building page " + address);
    this.m_currentAddress = address;
    let root = new inkCanvas();
    root.SetFitToContent(false);

    let ground = new inkRectangle();
    ground.SetAnchor(inkEAnchor.Fill);
    ground.SetTintColor(SlumlordColors.VoidColor());
    ground.Reparent(root);

    let sys = this.Sys();
    let col = SlumlordUi.Column(12.0);
    col.SetAnchor(inkEAnchor.TopLeft);
    col.SetMargin(new inkMargin(SlumlordUi.Px(24.0), SlumlordUi.Px(16.0), 0.0, 0.0));
    col.Reparent(root);

    if !IsDefined(sys) {
      SlumlordUi.Body("Slumlord is not running. Load a save and try again.", SlumlordColors.Trouble()).Reparent(col);
      return root;
    }
    sys.Refresh();

    let page = this.PageOf(address);
    if Equals(page, n"home") {
      page = sys.GetOwnedCount() > 0 ? n"holdings" : n"listings";
    }

    if !Equals(page, this.m_scrollPage) {
      this.m_scrollPage = page;
      this.m_scrollIndex = 0;
    }
    ArrayClear(this.m_rows);

    // Pinned: header and tabs (with the message line). Scrolls: everything in body.
    this.BuildHeader(col, sys);
    this.BuildTabs(col, Equals(page, n"renovate") ? n"holdings" : page, sys);
    let body = SlumlordUi.Column(12.0);
    body.Reparent(col);

    if Equals(page, n"listings") { this.BuildListings(body, sys, this.DistrictOf(address)); }
    if Equals(page, n"holdings") { this.BuildHoldings(body, sys, this.DistrictOf(address)); }
    if Equals(page, n"districts") { this.BuildDistricts(body, sys); }
    if Equals(page, n"collect") { this.BuildCollect(body, sys); }
    if Equals(page, n"renovate") { this.BuildRenovate(body, sys, this.PropertyOf(address)); }
    this.ApplyScroll();

    let scroller = new SlumlordScrollController();
    scroller.site = this;
    root.AttachController(scroller);
    return root;
  }

  private func PageOf(address: String) -> CName {
    if StrContains(address, "/listings") { return n"listings"; }
    if StrContains(address, "/holdings") { return n"holdings"; }
    if StrContains(address, "/districts") { return n"districts"; }
    if StrContains(address, "/collect") { return n"collect"; }
    if StrContains(address, "/renovate") { return n"renovate"; }
    return n"home";
  }

  private func DistrictOf(address: String) -> CName {
    if StrContains(address, "?d=") {
      return StringToName(StrAfterFirst(address, "?d="));
    }
    return n"";
  }

  private func PropertyOf(address: String) -> CName {
    if StrContains(address, "?p=") {
      return StringToName(StrAfterFirst(address, "?p="));
    }
    return n"";
  }

  private func Go(path: String) -> Void {
    if IsDefined(this.m_browser) { this.m_browser.SlumlordLoad(this.m_base + path); }
  }

  private func Reload() -> Void {
    if IsDefined(this.m_browser) { this.m_browser.SlumlordLoad(this.m_currentAddress); }
  }

  private func AddRow(body: ref<inkVerticalPanel>, row: ref<inkWidget>) -> Void {
    row.Reparent(body);
    ArrayPush(this.m_rows, row);
  }

  public func Scroll(delta: Int32) -> Void {
    this.m_scrollIndex += delta;
    this.ApplyScroll();
  }

  private func ApplyScroll() -> Void {
    let count = ArraySize(this.m_rows);
    let maxIndex = Max(count - 1, 0);
    this.m_scrollIndex = Clamp(this.m_scrollIndex, 0, maxIndex);
    let i = 0;
    while i < count {
      let row = this.m_rows[i];
      if IsDefined(row) { row.SetVisible(i >= this.m_scrollIndex); }
      i += 1;
    }
    if IsDefined(this.m_scrollHint) {
      let up = this.m_scrollIndex > 0;
      let down = this.m_scrollIndex < maxIndex;
      let hint = "Scroll";
      if SlumlordUi.GlyphsEnabled() {
        hint = (up ? "▲ " : "") + hint + (down ? " ▼" : "");
      }
      this.m_scrollHint.SetText(hint);
      this.m_scrollHint.SetVisible(count > 1);
    }
  }

  private func Say(text: String, kind: CName) -> Void {
    this.m_message = text;
    this.m_messageKind = kind;
  }

  // ================================================================== header, tabs, message

  private func BuildHeader(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>) -> Void {
    let row = SlumlordUi.Row(32.0);
    row.Reparent(parent);

    let wordmark = SlumlordUi.Text("SLUMLORD", 32.0, n"Bold", SlumlordColors.Chrome(), true);
    wordmark.SetVAlign(inkEVerticalAlign.Center);
    wordmark.Reparent(row);

    let waiting = sys.GetUncollectedTotal();
    SlumlordUi.Stat("Balance", SlumlordEconomy.FormatMoney(sys.GetPlayerMoney()), SlumlordColors.Gold()).Reparent(row);
    SlumlordUi.Stat("Rent waiting", SlumlordEconomy.FormatMoney(waiting), waiting > 0 ? SlumlordColors.Gold() : SlumlordColors.InkMuted()).Reparent(row);
    let allProperties = sys.GetProperties();
    SlumlordUi.Stat("Properties", IntToString(sys.GetOwnedCount()) + " / " + IntToString(ArraySize(allProperties)), SlumlordColors.Ink()).Reparent(row);
    SlumlordUi.Stat("Street Cred", IntToString(sys.GetStreetCred()), SlumlordColors.Ink()).Reparent(row);
    let days = sys.DaysUntilRentDay();
    SlumlordUi.Stat("Next rent day", days == 1 ? "Tomorrow" : "In " + IntToString(days) + " days", SlumlordColors.Ink()).Reparent(row);
  }

  private func BuildTabs(parent: ref<inkVerticalPanel>, active: CName, sys: ref<SlumlordSystem>) -> Void {
    let row = SlumlordUi.Row(8.0);
    row.Reparent(parent);
    this.AddTab(row, "Listings", n"listings", active);
    this.AddTab(row, "Holdings", n"holdings", active);
    this.AddTab(row, "Districts", n"districts", active);
    let collectLabel = sys.GetUncollectedTotal() > 0 && SlumlordUi.GlyphsEnabled() ? "Collect ◆" : "Collect";
    this.AddTab(row, collectLabel, n"collect", active);
    let hint = SlumlordUi.Caption("Scroll");
    hint.SetVAlign(inkEVerticalAlign.Center);
    hint.SetMargin(new inkMargin(SlumlordUi.Px(16.0), 0.0, 0.0, 0.0));
    hint.Reparent(row);
    this.m_scrollHint = hint;
    this.BuildMessage(row);
  }

  private func AddTab(row: ref<inkHorizontalPanel>, label: String, page: CName, active: CName) -> Void {
    let isActive = Equals(page, active);
    let tab = SlumlordUi.Button(label, page, 150.0, n"ghost", true);
    if isActive {
      // Active tab: ink label over a chrome bar.
      let bar = SlumlordUi.Rect(SlumlordUi.Px(150.0), SlumlordUi.Px(3.0), SlumlordColors.Chrome());
      SlumlordUi.Place(bar, 0.0, SlumlordUi.Px(33.0), tab);
    }
    SlumlordUi.OnClick(tab, this, n"OnTabPressed");
    tab.Reparent(row);
  }

  private func BuildMessage(parent: ref<inkCompoundWidget>) -> Void {
    let text = StrLen(this.m_message) > 0 ? this.m_message : " ";
    let color = Equals(this.m_messageKind, n"bad") ? SlumlordColors.Trouble() : SlumlordColors.Cyan();
    let line = SlumlordUi.Body(text, color);
    line.SetVAlign(inkEVerticalAlign.Center);
    line.SetMargin(new inkMargin(SlumlordUi.Px(24.0), 0.0, 0.0, 0.0));
    line.Reparent(parent);
    this.m_message = "";
  }

  // ================================================================== district chips

  private func BuildChips(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>, selected: CName, forHoldings: Bool) -> Void {
    let row = SlumlordUi.Row(8.0);
    this.AddRow(parent, row);
    for d in sys.GetDistricts() {
      let unlocked = sys.IsDistrictUnlocked(d.id);
      let owned = this.OwnedIn(sys, d.id);
      let label = d.displayName;
      let enabled = true;
      if forHoldings {
        label = label + " " + IntToString(owned);
        enabled = owned > 0;
      } else {
        // Locked districts show as disabled chips; the Districts tab shows their Street Cred requirement.
        enabled = unlocked;
      }
      let kind = Equals(d.id, selected) ? n"outline" : n"ghost";
      let chip = SlumlordUi.Button(label, d.id, 128.0, kind, enabled);
      SlumlordUi.OnClick(chip, this, forHoldings ? n"OnHoldingsChipPressed" : n"OnListingsChipPressed");
      chip.Reparent(row);
    }
  }

  private func OwnedIn(sys: ref<SlumlordSystem>, districtId: CName) -> Int32 {
    let count = 0;
    for p in sys.GetProperties() {
      if Equals(p.districtId, districtId) {
        let s = sys.GetState(p.id);
        if IsDefined(s) && s.owned { count += 1; }
      }
    }
    return count;
  }

  // Lays cards out in rows of `perRow`.
  private func Grid(parent: ref<inkVerticalPanel>, cards: array<ref<inkWidget>>, perRow: Int32) -> Void {
    let row: ref<inkHorizontalPanel>;
    let i = 0;
    for card in cards {
      if i % perRow == 0 {
        row = SlumlordUi.Row(12.0);
        this.AddRow(parent, row);
      }
      card.Reparent(row);
      i += 1;
    }
  }

  // ================================================================== listings

  private func BuildListings(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>, requested: CName) -> Void {
    let district = requested;
    if !IsNameValid(district) || !sys.IsDistrictUnlocked(district) {
      district = this.DefaultListingDistrict(sys);
    }
    this.BuildChips(parent, sys, district, false);

    let cards: array<ref<inkWidget>>;
    let money = sys.GetPlayerMoney();
    for p in sys.GetProperties() {
      let s = sys.GetState(p.id);
      if Equals(p.districtId, district) && IsDefined(s) && !s.owned {
        ArrayPush(cards, this.ListingCard(sys, p, money));
      }
    }
    if ArraySize(cards) == 0 {
      this.AddRow(parent, SlumlordUi.Body("Every property in this district is yours.", SlumlordColors.Gold()));
      return;
    }
    this.Grid(parent, cards, 4);
  }

  private func DefaultListingDistrict(sys: ref<SlumlordSystem>) -> CName {
    let firstUnlocked: CName;
    for d in sys.GetDistricts() {
      if sys.IsDistrictUnlocked(d.id) {
        if !IsNameValid(firstUnlocked) { firstUnlocked = d.id; }
        if this.OwnedIn(sys, d.id) < this.TotalIn(sys, d.id) { return d.id; }
      }
    }
    return firstUnlocked;
  }

  private func TotalIn(sys: ref<SlumlordSystem>, districtId: CName) -> Int32 {
    let count = 0;
    for p in sys.GetProperties() {
      if Equals(p.districtId, districtId) { count += 1; }
    }
    return count;
  }

  private func ListingCard(sys: ref<SlumlordSystem>, p: ref<SlumlordPropertyDef>, money: Int32) -> ref<inkWidget> {
    let w = SlumlordUi.Px(this.m_cardW);
    let h = SlumlordUi.Px(this.m_cardH);
    let pad = SlumlordUi.Px(14.0);
    let card = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), SlumlordColors.LineStrong(), 14.0);
    let district = sys.GetDistrictDef(p.districtId);
    let price = sys.GetPrice(p.id);

    let body = SlumlordUi.Column(8.0);
    SlumlordUi.Place(body, pad, pad, card);
    SlumlordUi.Tag("Vacant", n"vacant").Reparent(body);
    let title = SlumlordUi.Title(p.displayName);
    title.SetWrapping(true, w - 2.0 * pad);
    title.Reparent(body);

    let row1 = SlumlordUi.Row(16.0);
    row1.Reparent(body);
    SlumlordUi.Stat("Price", SlumlordEconomy.FormatMoney(price), SlumlordColors.Gold()).Reparent(row1);
    if p.commercial {
      SlumlordUi.Stat("Type", "Commercial", SlumlordColors.Ink()).Reparent(row1);
    } else {
      SlumlordUi.Stat("Units", IntToString(p.units), SlumlordColors.Ink()).Reparent(row1);
    }
    SlumlordUi.Stat("Est. weekly rent", SlumlordEconomy.FormatMoney(SlumlordEconomy.EstimatedWeeklyRent(p, district)), SlumlordColors.Gold()).Reparent(body);

    let affordable = money >= price;
    let buy = SlumlordUi.Button(affordable ? "Buy" : "Insufficient funds", p.id, 192.0, n"gold", affordable);
    SlumlordUi.OnClick(buy, this, n"OnBuyPressed");
    SlumlordUi.Place(buy, pad, h - pad - SlumlordUi.Px(36.0), card);
    return card;
  }

  // ================================================================== holdings

  private func BuildHoldings(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>, requested: CName) -> Void {
    if sys.GetOwnedCount() == 0 {
      this.AddRow(parent, SlumlordUi.Body("You own nothing yet. Check the listings.", SlumlordColors.InkMuted()));
      return;
    }
    let district = requested;
    if !IsNameValid(district) || this.OwnedIn(sys, district) == 0 {
      district = this.DefaultHoldingsDistrict(sys);
    }
    this.BuildChips(parent, sys, district, true);

    // Rent ready first, then the rest (trouble will sort above both once events exist).
    let ready: array<ref<inkWidget>>;
    let rest: array<ref<inkWidget>>;
    for p in sys.GetProperties() {
      let s = sys.GetState(p.id);
      if Equals(p.districtId, district) && IsDefined(s) && s.owned {
        if s.uncollected > 0 {
          ArrayPush(ready, this.HoldingCard(sys, p, s));
        } else {
          ArrayPush(rest, this.HoldingCard(sys, p, s));
        }
      }
    }
    for c in rest { ArrayPush(ready, c); }
    this.Grid(parent, ready, 4);
  }

  private func DefaultHoldingsDistrict(sys: ref<SlumlordSystem>) -> CName {
    let best: CName;
    let bestWaiting = -1;
    for d in sys.GetDistricts() {
      if this.OwnedIn(sys, d.id) > 0 {
        let waiting = this.WaitingIn(sys, d.id);
        if waiting > bestWaiting {
          best = d.id;
          bestWaiting = waiting;
        }
      }
    }
    return best;
  }

  private func WaitingIn(sys: ref<SlumlordSystem>, districtId: CName) -> Int32 {
    let total = 0;
    for p in sys.GetProperties() {
      if Equals(p.districtId, districtId) {
        let s = sys.GetState(p.id);
        if IsDefined(s) { total += s.uncollected; }
      }
    }
    return total;
  }

  private func HoldingCard(sys: ref<SlumlordSystem>, p: ref<SlumlordPropertyDef>, s: ref<SlumlordPropertyState>) -> ref<inkWidget> {
    let w = SlumlordUi.Px(this.m_cardW);
    let h = SlumlordUi.Px(this.m_holdingCardH);
    let pad = SlumlordUi.Px(14.0);
    let rentReady = s.uncollected > 0;
    let frame = rentReady ? SlumlordColors.Gold() : SlumlordColors.LineStrong();
    let card = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), frame, 14.0);

    let body = SlumlordUi.Column(8.0);
    SlumlordUi.Place(body, pad, pad, card);

    let top = SlumlordUi.Row(10.0);
    top.Reparent(body);
    SlumlordUi.RankBadge(s.rank).Reparent(top);
    if rentReady {
      SlumlordUi.Tag("Rent ready", n"rent").Reparent(top);
    } else {
      SlumlordUi.Tag("Secured", n"secured").Reparent(top);
    }

    let title = SlumlordUi.Title(p.displayName);
    title.SetWrapping(true, w - 2.0 * pad);
    title.Reparent(body);

    let row1 = SlumlordUi.Row(16.0);
    row1.Reparent(body);
    SlumlordUi.Stat("Weekly rent", SlumlordEconomy.FormatMoney(sys.GetWeeklyRent(p.id)), SlumlordColors.Gold()).Reparent(row1);
    SlumlordUi.Stat("Waiting", SlumlordEconomy.FormatMoney(s.uncollected), rentReady ? SlumlordColors.Gold() : SlumlordColors.InkMuted()).Reparent(row1);
    if p.commercial {
      SlumlordUi.Stat("Tenant", s.occupiedUnits > 0 ? "Business" : "Vacant", SlumlordColors.Cyan()).Reparent(body);
    } else {
      SlumlordUi.Stat("Occupancy", IntToString(s.occupiedUnits) + " / " + IntToString(p.units) + " units", SlumlordColors.Cyan()).Reparent(body);
    }

    let canRank = s.rank < SlumlordTuning.MaxRank();
    let renovate = SlumlordUi.Button(canRank ? "Renovate" : "Max rank", p.id, 192.0, n"outline", canRank);
    SlumlordUi.OnClick(renovate, this, n"OnRenovatePressed");
    SlumlordUi.Place(renovate, pad, h - pad - SlumlordUi.Px(36.0), card);
    return card;
  }

  // ================================================================== renovate (Contractors.reds)

  private func BuildRenovate(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>, id: CName) -> Void {
    let def = sys.GetPropertyDef(id);
    let s = sys.GetState(id);
    if !IsDefined(def) || !IsDefined(s) || !s.owned {
      this.AddRow(parent, SlumlordUi.Body("Pick one of your properties on the Holdings tab to renovate it.", SlumlordColors.InkMuted()));
      return;
    }
    this.m_renovateProperty = id;
    this.AddRow(parent, this.RenovateSummary(sys, def, s));

    // Available crews first, then locked ones (dimmed), each in roster order.
    let cards: array<ref<inkWidget>>;
    let locked: array<ref<inkWidget>>;
    for c in sys.GetContractors() {
      if sys.IsContractorAvailable(c) {
        ArrayPush(cards, this.ContractorCard(sys, def, s, c));
      } else {
        ArrayPush(locked, this.ContractorCard(sys, def, s, c));
      }
    }
    for c in locked { ArrayPush(cards, c); }
    this.Grid(parent, cards, 4);
  }

  // One strip: rank badge, name, progress to the next rank, jobs left this week, back to holdings.
  private func RenovateSummary(sys: ref<SlumlordSystem>, def: ref<SlumlordPropertyDef>, s: ref<SlumlordPropertyState>) -> ref<inkWidget> {
    let w = SlumlordUi.Px(1000.0);
    let h = SlumlordUi.Px(76.0);
    let pad = SlumlordUi.Px(14.0);
    let panel = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), SlumlordColors.LineStrong(), 14.0);
    let row = SlumlordUi.Row(28.0);
    SlumlordUi.Place(row, pad, pad, panel);

    SlumlordUi.RankBadge(s.rank).Reparent(row);
    let name = SlumlordUi.Column(2.0);
    name.Reparent(row);
    SlumlordUi.Title(def.displayName).Reparent(name);
    SlumlordUi.Caption(def.commercial ? "Commercial" : "Residential, " + IntToString(def.units) + " units").Reparent(name);

    let needed = sys.GetRankPointsNeeded(def.id);
    let progress = SlumlordUi.Column(6.0);
    progress.Reparent(row);
    if needed > 0 {
      SlumlordUi.Caption("Progress to rank " + SlumlordEconomy.RankLetter(s.rank + 1) + "  " + IntToString(s.rankPoints) + " / " + IntToString(needed) + " points").Reparent(progress);
      SlumlordUi.ProgressBar(300.0, Cast<Float>(s.rankPoints) / Cast<Float>(needed), SlumlordColors.Cyan()).Reparent(progress);
    } else {
      SlumlordUi.Caption("Top rank").Reparent(progress);
      SlumlordUi.ProgressBar(300.0, 1.0, SlumlordColors.Gold()).Reparent(progress);
    }

    let jobsLeft = sys.GetJobsLeft(def.id);
    SlumlordUi.Stat("Jobs left this week", IntToString(jobsLeft) + " of " + IntToString(SlumlordTuning.JobsPerRentDay()), jobsLeft > 0 ? SlumlordColors.Ink() : SlumlordColors.InkMuted()).Reparent(row);

    let back = SlumlordUi.Button("Holdings", def.districtId, 150.0, n"ghost", true);
    SlumlordUi.OnClick(back, this, n"OnHoldingsChipPressed");
    SlumlordUi.Place(back, w - pad - SlumlordUi.Px(150.0), pad, panel);
    return panel;
  }

  private func ContractorCard(sys: ref<SlumlordSystem>, def: ref<SlumlordPropertyDef>, s: ref<SlumlordPropertyState>, c: ref<SlumlordContractorDef>) -> ref<inkWidget> {
    let w = SlumlordUi.Px(this.m_cardW);
    let h = SlumlordUi.Px(this.m_contractorCardH);
    let pad = SlumlordUi.Px(14.0);
    let available = sys.IsContractorAvailable(c);
    let card = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), SlumlordColors.LineStrong(), 14.0);
    if !available { card.SetOpacity(0.55); }

    let body = SlumlordUi.Column(6.0);
    SlumlordUi.Place(body, pad, pad, card);
    let title = SlumlordUi.Title(c.crew);
    title.SetWrapping(true, w - 2.0 * pad);
    title.Reparent(body);
    SlumlordUi.Body(c.boss, SlumlordColors.InkMuted()).Reparent(body);
    SlumlordUi.StarMeter(c.stars).Reparent(body);

    let fit = SlumlordContractors.Fit(c, def);
    let fitText = SlumlordContractors.FitWord(fit) + (def.commercial ? " with shops" : " with apartments");
    if SlumlordUi.GlyphsEnabled() { fitText = SlumlordContractors.FitGlyph(fit) + " " + fitText; }
    let fitColor = fit >= 2 ? SlumlordColors.Cyan() : (fit == 1 ? SlumlordColors.InkMuted() : SlumlordColors.Trouble());
    SlumlordUi.Data(fitText, fitColor).Reparent(body);

    let stats = SlumlordUi.Row(16.0);
    stats.Reparent(body);
    SlumlordUi.Stat("Fee", SlumlordEconomy.FormatMoney(SlumlordTuning.ContractorFee(c.stars)), SlumlordColors.Gold()).Reparent(stats);
    SlumlordUi.Stat("Work", "+" + IntToString(SlumlordContractors.JobPoints(c, def)) + " pts", SlumlordColors.Ink()).Reparent(stats);

    let label = "Hire";
    let enabled = true;
    switch sys.CanHire(def.id, c.id) {
      case SlumlordHireResult.Progress: break;
      case SlumlordHireResult.ContractorLocked:
        label = IsNameValid(c.districtId) ? "Street Cred " + IntToString(sys.GetDistrictDef(c.districtId).streetCredRequired) : "Unlocked by a gig";
        enabled = false;
        break;
      case SlumlordHireResult.NotEnoughMoney: label = "Insufficient funds"; enabled = false; break;
      case SlumlordHireResult.JobLimit: label = "No jobs left"; enabled = false; break;
      case SlumlordHireResult.MaxRank: label = "Max rank"; enabled = false; break;
      default: label = "Unavailable"; enabled = false;
    }
    let hire = SlumlordUi.Button(label, c.id, 192.0, n"gold", enabled);
    SlumlordUi.OnClick(hire, this, n"OnHirePressed");
    SlumlordUi.Place(hire, pad, h - pad - SlumlordUi.Px(36.0), card);
    return card;
  }

  // ================================================================== districts

  private func BuildDistricts(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>) -> Void {
    let cards: array<ref<inkWidget>>;
    for d in sys.GetDistricts() {
      ArrayPush(cards, this.DistrictCard(sys, d));
    }
    this.Grid(parent, cards, 3);
  }

  // Compact: frame colour carries the state (gold = dominated), so no tag row.
  private func DistrictCard(sys: ref<SlumlordSystem>, d: ref<SlumlordDistrictDef>) -> ref<inkWidget> {
    let w = SlumlordUi.Px(this.m_districtCardW);
    let h = SlumlordUi.Px(this.m_districtCardH);
    let pad = SlumlordUi.Px(14.0);
    let unlocked = sys.IsDistrictUnlocked(d.id);
    let owned = this.OwnedIn(sys, d.id);
    let total = this.TotalIn(sys, d.id);
    let dominated = total > 0 && owned == total;
    let frame = dominated ? SlumlordColors.Gold() : SlumlordColors.LineStrong();
    let card = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), frame, 14.0);

    let body = SlumlordUi.Column(6.0);
    SlumlordUi.Place(body, pad, pad, card);
    SlumlordUi.Title(d.displayName).Reparent(body);

    if !unlocked {
      SlumlordUi.Caption("Locked").Reparent(body);
      SlumlordUi.Stat("Unlocks at", "Street Cred " + IntToString(d.streetCredRequired), SlumlordColors.Ink()).Reparent(body);
      return card;
    }

    let control = SlumlordUi.Column(4.0);
    control.Reparent(body);
    let label = dominated ? "Dominated" : "District control " + IntToString(sys.GetDistrictControl(d.id)) + "%";
    SlumlordUi.Caption(label).Reparent(control);
    SlumlordUi.ControlMeter(owned, total).Reparent(control);
    SlumlordUi.Stat("Rival", sys.IsRivalMet(d.id) ? d.rival : "Unknown", SlumlordColors.Ink()).Reparent(body);
    return card;
  }

  // ================================================================== collect

  // Side by side so it fits the page height: ledger on the left, total and Collect on the right.
  private func BuildCollect(parent: ref<inkVerticalPanel>, sys: ref<SlumlordSystem>) -> Void {
    let w = SlumlordUi.Px(1000.0);
    let h = SlumlordUi.Px(250.0);
    let pad = SlumlordUi.Px(20.0);
    let waiting = sys.GetUncollectedTotal();
    let frame = waiting > 0 ? SlumlordColors.Gold() : SlumlordColors.LineStrong();
    let panel = SlumlordUi.Panel(w, h, SlumlordColors.Panel(), frame, 24.0);
    this.AddRow(parent, panel);

    // Left: title and ledger, one line per district with rent waiting.
    let left = SlumlordUi.Column(8.0);
    SlumlordUi.Place(left, pad, pad, panel);
    SlumlordUi.Title("Collection").Reparent(left);
    let ledger = SlumlordUi.Row(40.0);
    ledger.Reparent(left);
    let names = SlumlordUi.Column(2.0);
    let amounts = SlumlordUi.Column(2.0);
    names.Reparent(ledger);
    amounts.Reparent(ledger);
    let lines = 0;
    for d in sys.GetDistricts() {
      let inDistrict = this.WaitingIn(sys, d.id);
      if inDistrict > 0 {
        SlumlordUi.Data(d.displayName, SlumlordColors.InkMuted()).Reparent(names);
        SlumlordUi.Data(SlumlordEconomy.FormatMoney(inDistrict), SlumlordColors.Gold()).Reparent(amounts);
        lines += 1;
      }
    }
    if lines == 0 {
      let days = sys.DaysUntilRentDay();
      SlumlordUi.Body("Nothing waiting. Next rent day " + (days == 1 ? "tomorrow." : "in " + IntToString(days) + " days."), SlumlordColors.InkMuted()).Reparent(names);
    }

    // Right: total and the Collect button.
    let rightX = SlumlordUi.Px(540.0);
    let right = SlumlordUi.Column(6.0);
    SlumlordUi.Place(right, rightX, pad, panel);
    SlumlordUi.Caption("Total").Reparent(right);
    SlumlordUi.MoneyXL(SlumlordEconomy.FormatMoney(waiting)).Reparent(right);

    let collect = SlumlordUi.Button("Collect", n"collect", 260.0, n"gold", waiting > 0);
    SlumlordUi.OnClick(collect, this, n"OnCollectPressed");
    SlumlordUi.Place(collect, rightX, h - pad - SlumlordUi.Px(36.0), panel);

    if this.m_lastCollected > 0 {
      let stamp = SlumlordUi.Text("Paid", 28.0, n"Bold", SlumlordColors.Chrome(), true);
      stamp.SetRenderTransformPivot(new Vector2(0.5, 0.5));
      stamp.SetRotation(-8.0);
      SlumlordUi.Place(stamp, rightX + SlumlordUi.Px(290.0), h - pad - SlumlordUi.Px(40.0), panel);
      this.m_lastCollected = 0;
    }
  }

  // ================================================================== input

  protected cb func OnTabPressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      SlumlordUi.PlaySound(n"ui_menu_onpress");
      this.Go("/" + NameToString(evt.GetCurrentTarget().GetName()));
    }
    return false;
  }

  protected cb func OnListingsChipPressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      SlumlordUi.PlaySound(n"ui_menu_onpress");
      this.Go("/listings?d=" + NameToString(evt.GetCurrentTarget().GetName()));
    }
    return false;
  }

  protected cb func OnHoldingsChipPressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      SlumlordUi.PlaySound(n"ui_menu_onpress");
      this.Go("/holdings?d=" + NameToString(evt.GetCurrentTarget().GetName()));
    }
    return false;
  }

  protected cb func OnBuyPressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      let sys = this.Sys();
      if !IsDefined(sys) { return false; }
      let id = evt.GetCurrentTarget().GetName();
      let def = sys.GetPropertyDef(id);
      let result = sys.Buy(id);
      switch result {
        case SlumlordBuyResult.Ok:
          SlumlordUi.PlaySound(n"ui_menu_onpress");
          this.Say("Acquired. " + def.displayName + " is yours.", n"good");
          break;
        case SlumlordBuyResult.NotEnoughMoney:
          this.Say("Insufficient funds.", n"bad");
          break;
        case SlumlordBuyResult.DistrictLocked:
          this.Say("District locked. Raise your Street Cred.", n"bad");
          break;
        case SlumlordBuyResult.AlreadyOwned:
          this.Say("Already yours.", n"bad");
          break;
        default:
          this.Say("Purchase failed.", n"bad");
      }
      this.Reload();
    }
    return false;
  }

  protected cb func OnRenovatePressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      SlumlordUi.PlaySound(n"ui_menu_onpress");
      this.Go("/renovate?p=" + NameToString(evt.GetCurrentTarget().GetName()));
    }
    return false;
  }

  protected cb func OnHirePressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      let sys = this.Sys();
      if !IsDefined(sys) { return false; }
      let contractorId = evt.GetCurrentTarget().GetName();
      let c = sys.GetContractorDef(contractorId);
      let def = sys.GetPropertyDef(this.m_renovateProperty);
      if !IsDefined(c) || !IsDefined(def) { return false; }
      let points = SlumlordContractors.JobPoints(c, def);
      switch sys.Hire(this.m_renovateProperty, contractorId) {
        case SlumlordHireResult.RankedUp:
          SlumlordUi.PlaySound(n"ui_menu_onpress");
          this.Say(c.crew + " finished. " + def.displayName + " is now rank " + SlumlordEconomy.RankLetter(sys.GetState(def.id).rank) + ".", n"good");
          break;
        case SlumlordHireResult.Progress:
          SlumlordUi.PlaySound(n"ui_menu_onpress");
          this.Say(c.crew + " did the work: +" + IntToString(points) + " points.", n"good");
          break;
        case SlumlordHireResult.NotEnoughMoney:
          this.Say("Insufficient funds.", n"bad");
          break;
        case SlumlordHireResult.JobLimit:
          this.Say("No more jobs here until rent day.", n"bad");
          break;
        case SlumlordHireResult.MaxRank:
          this.Say("Already top rank.", n"bad");
          break;
        case SlumlordHireResult.ContractorLocked:
          this.Say("That crew isn't available yet.", n"bad");
          break;
        default:
          this.Say("Hire failed.", n"bad");
      }
      this.Reload();
    }
    return false;
  }

  protected cb func OnCollectPressed(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"click") || evt.IsAction(n"tap") {
      evt.Consume();
      let sys = this.Sys();
      if !IsDefined(sys) { return false; }
      let amount = sys.Collect();
      if amount > 0 {
        SlumlordUi.PlaySound(n"ui_menu_onpress");
        this.m_lastCollected = amount;
        this.Say("Collected " + SlumlordEconomy.FormatMoney(amount) + ".", n"good");
      }
      this.Reload();
    }
    return false;
  }
}

// Mouse wheel scrolling for Slumlord pages, the way the game's own UI reads the wheel
// (global OnPostOnRelative input, action mouse_wheel). One notch = one row.
public class SlumlordScrollController extends inkLogicController {
  public let site: wref<SlumlordSite>;

  protected cb func OnInitialize() -> Bool {
    this.RegisterToGlobalInputCallback(n"OnPostOnRelative", this, n"OnSlumlordAxis");
    return true;
  }

  protected cb func OnUninitialize() -> Bool {
    this.UnregisterFromGlobalInputCallback(n"OnPostOnRelative", this, n"OnSlumlordAxis");
    return true;
  }

  protected cb func OnSlumlordAxis(evt: ref<inkPointerEvent>) -> Bool {
    if evt.IsAction(n"mouse_wheel") && IsDefined(this.site) {
      let axis = evt.GetAxisData();
      if axis > 0.0 {
        this.site.Scroll(-1);
      } else {
        if axis < 0.0 { this.site.Scroll(1); }
      }
    }
    return false;
  }
}
