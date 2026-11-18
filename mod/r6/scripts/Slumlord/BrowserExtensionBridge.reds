// Optional: when Browser Extension Framework is installed, it replaces the NETdir home page, so
// Slumlord registers there to get listed. Everything here compiles only if that framework exists;
// without it, Browser.reds lists the site itself. Pages are always built by SlumlordSite.
module Slumlord

@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.DataStructures.*
@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.Classes.*

@if(ModuleExists("BrowserExtension.System"))
public class SlumlordBrowserExtensionListener extends BrowserEventsListener {
  public func Init(logic: ref<BrowserGameController>) {
    super.Init(logic);
    this.m_siteData.address = SlumlordSite.BaseAddress();
    this.m_siteData.shortName = SlumlordSite.ShortName();
    // Icon: the framework's default until the Slumlord icon atlas exists.
  }

  public func GetWebPage(address: String) -> ref<inkCompoundWidget> {
    let browser = this.m_deviceLogicController.SlumlordBrowser();
    if !IsDefined(browser) { return null; }
    return browser.GetSlumlordSite().GetWebPage(address);
  }
}

@if(ModuleExists("BrowserExtension.System"))
@addMethod(BrowserGameController)
public func SlumlordBrowser() -> wref<BrowserController> {
  return inkWidgetRef.GetController(this.m_logicControllerRef) as BrowserController;
}

@if(ModuleExists("BrowserExtension.System"))
@addField(BrowserGameController)
private let m_slumlordListener: ref<SlumlordBrowserExtensionListener>;

@if(ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserGameController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  this.m_slumlordListener = new SlumlordBrowserExtensionListener();
  this.m_slumlordListener.Init(this);
  return result;
}

@if(ModuleExists("BrowserExtension.System"))
@wrapMethod(BrowserGameController)
protected cb func OnUninitialize() -> Bool {
  let result: Bool = wrappedMethod();
  if IsDefined(this.m_slumlordListener) {
    this.m_slumlordListener.Uninit();
    this.m_slumlordListener = null;
  }
  return result;
}
