// Optional link with Marmur Bank (module NightCityBank, by the Marmur Bank / ANODOS author). Slumlord works
// the same without it. With it, and with a Marmur account open:
//  1 Rent, purchases and contractor fees post to Marmur's ledger as named Real Estate entries
//    ("Slumlord Realty" / the crew's name, with the property in the detail), the way Marmur labels Delamain fares.
//  2 Purchases and contractor fees can draw on Marmur checking when V's wallet is short, if Marmur's own
//    overdraft setting is on. Marmur moves the shortfall into the wallet and refunds anything left over.
// Marmur is reached only through Codeware reflection, so Slumlord compiles and runs without it (redscript can't
// import a module that may not exist). Functions used, all public on NightCityBank.NCBankSystem / NCBankAPI:
//   NCBankAPI.IsBankingSuppressed / IsRuntimeReady / IsAccountOpen,
//   NCBankSystem.GetWalletBalance / GetTransactionSequence / BeginSourceContext26 / EndSourceContext26 /
//   CapturePaymentSource26 / GetCheckingSpendingPower / BeginCheckingTransaction / FinishCheckingTransaction.
// If any is missing (Marmur changed its API), the link stays off and Slumlord logs which one.
module Slumlord

public class SlumlordBankEntry {
  public let before: Int32;
  public let sequence: Int32;
}

public class SlumlordBankAuth {
  public let token: Variant;     // ref<NightCityBank.NCBankCheckingAuthorization>, held opaquely
  public let used: Bool;         // the bank was asked to cover a shortfall
}

public abstract class SlumlordBank {
  public static func SubjectRealEstate() -> Int32 { return 10; }   // Marmur's spending subject "Real Estate"

  private static func Api() -> ref<ReflectionClass> { return Reflection.GetClass(n"NightCityBank.NCBankAPI"); }
  private static func SystemClass() -> ref<ReflectionClass> { return Reflection.GetClass(n"NightCityBank.NCBankSystem"); }

  // Installed, and the API has everything Slumlord calls.
  public static func Installed() -> Bool {
    return Equals(SlumlordBank.MissingApi(), "");
  }

  // "" when complete, "none" when Marmur isn't installed, else the first missing function.
  public static func MissingApi() -> String {
    let api = SlumlordBank.Api();
    let sys = SlumlordBank.SystemClass();
    if !IsDefined(api) || !IsDefined(sys) { return "none"; }
    for n in [n"IsBankingSuppressed", n"IsRuntimeReady", n"IsAccountOpen"] {
      if !IsDefined(api.GetStaticFunction(n)) { return "NCBankAPI." + NameToString(n); }
    }
    for n in [n"GetWalletBalance", n"GetTransactionSequence", n"BeginSourceContext26", n"EndSourceContext26",
              n"CapturePaymentSource26", n"GetCheckingSpendingPower", n"BeginCheckingTransaction", n"FinishCheckingTransaction"] {
      if !IsDefined(sys.GetFunction(n)) { return "NCBankSystem." + NameToString(n); }
    }
    if !IsDefined(Reflection.GetClass(n"NightCityBank.NCBankCheckingAuthorization")) { return "NCBankCheckingAuthorization"; }
    return "";
  }

  // Marmur's system, when the link can be used right now: installed, not suppressed (Johnny sections),
  // runtime ready and V has an account. Null otherwise.
  public static func System(game: GameInstance) -> ref<IScriptable> {
    if !SlumlordBank.Installed() { return null; }
    let api = SlumlordBank.Api();
    if SlumlordBank.StaticBool(api, n"IsBankingSuppressed", game, true) { return null; }
    if !SlumlordBank.StaticBool(api, n"IsRuntimeReady", game, false) { return null; }
    if !SlumlordBank.StaticBool(api, n"IsAccountOpen", game, false) { return null; }
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"NightCityBank.NCBankSystem");
  }

  public static func Linked(game: GameInstance) -> Bool { return IsDefined(SlumlordBank.System(game)); }

  // ---- 2: spending power and checking cover ----

  // Wallet plus Marmur checking when Marmur would cover a shortfall (its overdraft setting on), else the wallet.
  public static func SpendingPower(game: GameInstance, wallet: Int32) -> Int32 {
    let sys = SlumlordBank.System(game);
    if !IsDefined(sys) { return wallet; }
    let ok: Bool;
    let v = SlumlordBank.SystemClass().GetFunction(n"GetCheckingSpendingPower").Call(sys, [ToVariant(game)], ok);
    let power = ok ? FromVariant<Int32>(v) : wallet;
    return Max(wallet, power);
  }

  // Before a payment: if the wallet is short, ask Marmur to move the shortfall in from checking.
  // Returns null when no bank help is needed or possible (then just try the wallet).
  public static func Authorize(game: GameInstance, amount: Int32, wallet: Int32) -> ref<SlumlordBankAuth> {
    if wallet >= amount { return null; }
    let sys = SlumlordBank.System(game);
    if !IsDefined(sys) || SlumlordBank.SpendingPower(game, wallet) < amount { return null; }   // no doomed request: Marmur logs denials
    let ok: Bool;
    let token = SlumlordBank.SystemClass().GetFunction(n"BeginCheckingTransaction").Call(sys, [ToVariant(game), ToVariant(amount)], ok);
    if !ok { return null; }
    let auth = new SlumlordBankAuth();
    auth.token = token;
    auth.used = true;
    return auth;
  }

  // After the payment: Marmur records what it covered and returns anything unspent to checking.
  public static func Settle(game: GameInstance, auth: ref<SlumlordBankAuth>, succeeded: Bool) -> Void {
    if !IsDefined(auth) || !auth.used { return; }
    let sys = GameInstance.GetScriptableSystemsContainer(game).Get(n"NightCityBank.NCBankSystem");
    if !IsDefined(sys) { return; }
    let ok: Bool;
    SlumlordBank.SystemClass().GetFunction(n"FinishCheckingTransaction").Call(sys, [ToVariant(game), auth.token, ToVariant(succeeded)], ok);
    auth.used = false;
  }

  // ---- 1: named ledger entries ----

  // Call right before Slumlord changes V's wallet; Marmur then knows the change is Slumlord's.
  public static func Begin(game: GameInstance) -> ref<SlumlordBankEntry> {
    let sys = SlumlordBank.System(game);
    if !IsDefined(sys) { return null; }
    let cls = SlumlordBank.SystemClass();
    let ok: Bool;
    cls.GetFunction(n"BeginSourceContext26").Call(sys, [], ok);
    let entry = new SlumlordBankEntry();
    entry.before = FromVariant<Int32>(cls.GetFunction(n"GetWalletBalance").Call(sys, [ToVariant(game)], ok));
    entry.sequence = FromVariant<Int32>(cls.GetFunction(n"GetTransactionSequence").Call(sys, [], ok));
    return entry;
  }

  // Right after the wallet change: names it in Marmur's ledger (Real Estate).
  public static func End(game: GameInstance, entry: ref<SlumlordBankEntry>, label: String, detail: String) -> Void {
    if !IsDefined(entry) { return; }
    let sys = GameInstance.GetScriptableSystemsContainer(game).Get(n"NightCityBank.NCBankSystem");
    if !IsDefined(sys) { return; }
    let cls = SlumlordBank.SystemClass();
    let ok: Bool;
    cls.GetFunction(n"EndSourceContext26").Call(sys, [], ok);
    let after = FromVariant<Int32>(cls.GetFunction(n"GetWalletBalance").Call(sys, [ToVariant(game)], ok));
    if after == entry.before { return; }
    cls.GetFunction(n"CapturePaymentSource26").Call(sys, [ToVariant(game), ToVariant(label), ToVariant(detail),
      ToVariant(SlumlordBank.SubjectRealEstate()), ToVariant(entry.before), ToVariant(after), ToVariant(entry.sequence)], ok);
    if !ok { ModLog(n"Slumlord", "Marmur Bank: could not label " + label + " (" + detail + ")"); }
  }

  // ---- debug ----

  public static func Describe(game: GameInstance) -> String {
    let missing = SlumlordBank.MissingApi();
    if Equals(missing, "none") { return "Marmur Bank: not installed"; }
    if NotEquals(missing, "") { return "Marmur Bank: installed, link OFF (missing " + missing + ")"; }
    if !SlumlordBank.Linked(game) { return "Marmur Bank: installed, link idle (no account open, suppressed, or not ready)"; }
    let player = GetPlayer(game);
    let wallet = IsDefined(player) ? GameInstance.GetTransactionSystem(game).GetItemQuantity(player, MarketSystem.Money()) : 0;
    return "Marmur Bank: linked. Wallet " + SlumlordEconomy.FormatMoney(wallet) + ", spending power with checking "
      + SlumlordEconomy.FormatMoney(SlumlordBank.SpendingPower(game, wallet));
  }

  private static func StaticBool(api: ref<ReflectionClass>, name: CName, game: GameInstance, fallback: Bool) -> Bool {
    let ok: Bool;
    let v = api.GetStaticFunction(name).Call([ToVariant(game)], ok);
    return ok ? FromVariant<Bool>(v) : fallback;
  }
}
