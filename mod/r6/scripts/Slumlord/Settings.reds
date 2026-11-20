// Player options. With Mod Settings installed they appear under Settings > Mods > Slumlord; without it the defaults
// below apply and nothing else changes. Mod Settings is optional: only the listener calls are guarded with
// @if(ModuleExists("ModSettingsModule")) (the way Night City Press Wire does it); the @runtimeProperty tags are
// plain metadata that compile either way.
//
// Read them with SlumlordSettings.Get(). Changes apply at once: prices, rent and fees are worked out when shown or
// charged, tenant rates on the next rent day, pins are redrawn when a setting changes.
module Slumlord

public class SlumlordSettings extends IScriptable {

  // ---- Economy

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Economy")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.order", "1")
  @runtimeProperty("ModSettings.displayName", "Rent")
  @runtimeProperty("ModSettings.description", "Multiplies every rent: what tenants pay each week and the estimates on listings. 1.00 is the designed balance.")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.25")
  @runtimeProperty("ModSettings.max", "3.0")
  public let rentMultiplier: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Economy")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.order", "2")
  @runtimeProperty("ModSettings.displayName", "Property prices")
  @runtimeProperty("ModSettings.description", "Multiplies what properties cost to buy. Renovation targets stay tied to the base price.")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.25")
  @runtimeProperty("ModSettings.max", "3.0")
  public let priceMultiplier: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Economy")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.order", "3")
  @runtimeProperty("ModSettings.displayName", "Contractor fees")
  @runtimeProperty("ModSettings.description", "Multiplies what each renovation job costs.")
  @runtimeProperty("ModSettings.step", "0.05")
  @runtimeProperty("ModSettings.min", "0.25")
  @runtimeProperty("ModSettings.max", "3.0")
  public let contractorFeeMultiplier: Float = 1.0;

  // ---- Tenants

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Tenants")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.order", "1")
  @runtimeProperty("ModSettings.displayName", "New tenants")
  @runtimeProperty("ModSettings.description", "Multiplies how often new tenants move into empty units. 0 stops arrivals. Rank S properties still fill every week.")
  @runtimeProperty("ModSettings.step", "0.1")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "3.0")
  public let arrivalMultiplier: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Tenants")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.order", "2")
  @runtimeProperty("ModSettings.displayName", "Move-outs")
  @runtimeProperty("ModSettings.description", "Multiplies the weekly chance that a tenant or business leaves. 0 means nobody leaves on their own (lease-broken events still happen).")
  @runtimeProperty("ModSettings.step", "0.1")
  @runtimeProperty("ModSettings.min", "0.0")
  @runtimeProperty("ModSettings.max", "3.0")
  public let moveOutMultiplier: Float = 1.0;

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Tenants")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.order", "3")
  @runtimeProperty("ModSettings.displayName", "Weekly tenant report")
  @runtimeProperty("ModSettings.description", "Slumlord Realty texts you a summary of move-ins and move-outs on each rent day.")
  public let weeklyReport: Bool = true;

  // ---- Rivals

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Rivals")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.order", "1")
  @runtimeProperty("ModSettings.displayName", "Finger's harassment (%)")
  @runtimeProperty("ModSettings.description", "While Quentin Finger is after you, the chance per Santo Domingo property per week that he drives a tenant out. Designed at 20.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "100")
  public let fingerHarassPercent: Int32 = 20;

  // ---- Map

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Map")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.order", "1")
  @runtimeProperty("ModSettings.displayName", "Property pins")
  @runtimeProperty("ModSettings.description", "Show Slumlord's property pins (listings and holdings) on the map. Quest pins are not affected.")
  public let showPins: Bool = true;

  // ---- Marmur Bank (only with Marmur Bank installed and an account open)

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Marmur Bank")
  @runtimeProperty("ModSettings.category.order", "5")
  @runtimeProperty("ModSettings.order", "1")
  @runtimeProperty("ModSettings.displayName", "Name entries in Marmur")
  @runtimeProperty("ModSettings.description", "Rent, purchases and contractor fees show in Marmur's activity as Real Estate entries from Slumlord Realty or the crew. Needs Marmur Bank.")
  public let marmurLedger: Bool = true;

  @runtimeProperty("ModSettings.mod", "Slumlord")
  @runtimeProperty("ModSettings.category", "Marmur Bank")
  @runtimeProperty("ModSettings.category.order", "5")
  @runtimeProperty("ModSettings.order", "2")
  @runtimeProperty("ModSettings.displayName", "Pay from savings")
  @runtimeProperty("ModSettings.description", "When your cash is short, purchases and contractor fees draw the rest from Marmur savings. Needs Marmur Bank with Overdraft Protection turned on.")
  public let marmurOverdraft: Bool = true;

  public static func Get() -> ref<SlumlordSettings> {
    let sys = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"Slumlord.SlumlordSettingsSystem") as SlumlordSettingsSystem;
    if IsDefined(sys) {
      let s = sys.Settings();
      if IsDefined(s) { return s; }
    }
    return new SlumlordSettings();
  }

  // Mod Settings calls this after any change (RegisterListenerToModifications).
  public cb func OnModSettingsChange() -> Void {
    let system = SlumlordSystem.GetInstance(GetGameInstance());
    if IsDefined(system) { system.RefreshPins(); }
  }
}

// Owns the live settings object, kept up to date by Mod Settings while the game runs.
public class SlumlordSettingsSystem extends ScriptableSystem {
  private let m_settings: ref<SlumlordSettings>;

  private func OnAttach() -> Void {
    this.m_settings = new SlumlordSettings();
    this.Listen(this.m_settings);
  }

  private func OnDetach() -> Void {
    this.Unlisten(this.m_settings);
  }

  public func Settings() -> ref<SlumlordSettings> { return this.m_settings; }

  @if(ModuleExists("ModSettingsModule"))
  private func Listen(s: ref<SlumlordSettings>) -> Void {
    ModSettings.RegisterListenerToClass(s);
    ModSettings.RegisterListenerToModifications(s);
  }
  @if(!ModuleExists("ModSettingsModule"))
  private func Listen(s: ref<SlumlordSettings>) -> Void {}

  @if(ModuleExists("ModSettingsModule"))
  private func Unlisten(s: ref<SlumlordSettings>) -> Void {
    ModSettings.UnregisterListenerToModifications(s);
    ModSettings.UnregisterListenerToClass(s);
  }
  @if(!ModuleExists("ModSettingsModule"))
  private func Unlisten(s: ref<SlumlordSettings>) -> Void {}
}
