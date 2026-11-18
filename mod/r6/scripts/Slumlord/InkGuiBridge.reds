// Home page link when InkGUI is installed (it ships inside Night City Allies).
//
// Without Browser Extension Framework, InkGUI lists its sites by rebuilding the NETdir home page: it moves
// the link panel into a scroll box, hides the vanilla rows (linkBar01/02, where SetSlot writes), and lays
// out rows of its own "link" cells, 5 per row. Slumlord adds one more cell of the same kind at the end of
// that grid. Clicks go through the game's link handling (OnLinkPressed -> LoadWebPage), as with SetSlot.
// InkGUI's LoadWebPage hook only serves addresses of sites registered with it, so ours passes through.
module Slumlord

@if(ModuleExists("InkGUI"))
import InkGUI.*

public abstract class SlumlordInkGui {
  public static func CellName() -> CName { return n"slumlord_home_link"; }
}

// True when InkGUI will rebuild the home page: it does so only when it has sites to list.
@if(ModuleExists("InkGUI"))
@addMethod(WebPage)
public func SlumlordInkGuiOwnsHome() -> Bool {
  let sites: array<ref<InkGUIWebsite>> = InkGUIWebsiteSystem.Get().GetWebsites();
  return ArraySize(sites) > 0;
}

@if(!ModuleExists("InkGUI"))
@addMethod(WebPage)
public func SlumlordInkGuiOwnsHome() -> Bool {
  return false;
}

// Adds the Slumlord cell to InkGUI's grid. False while the grid does not exist yet.
@if(ModuleExists("InkGUI"))
@addMethod(WebPage)
public func SlumlordAddInkGuiLink() -> Bool {
  let panel: wref<inkCompoundWidget> = this.SlumlordInkGuiPanel();
  if !IsDefined(panel) {
    return false;
  }

  // The last visible row; the hidden vanilla rows and the network header come first in the panel.
  let row: wref<inkCompoundWidget>;
  let i: Int32 = 0;
  while i < panel.GetNumChildren() {
    let child = panel.GetWidgetByIndex(i) as inkHorizontalPanel;
    if IsDefined(child) && child.IsVisible() {
      if IsDefined(child.GetWidgetByPathName(SlumlordInkGui.CellName())) {
        return true;
      }
      row = child;
    }
    i += 1;
  }
  if !IsDefined(row) {
    return false;
  }

  if row.GetNumChildren() >= InkGUIHomePage.CellsPerRow() {
    let newRow = new inkHorizontalPanel();
    newRow.SetHAlign(inkEHorizontalAlign.Left);
    newRow.SetChildMargin(new inkMargin(InkGUIHomePage.CellGap(), 0.0, InkGUIHomePage.CellGap(), 0.0));
    newRow.Reparent(panel);
    row = newRow;
  }

  let cell = this.SpawnFromExternal(row, InkGUIStyle.LibraryPath(), InkGUIHomePage.LinkName()) as inkCompoundWidget;
  if !IsDefined(cell) {
    return false;
  }
  cell.SetName(SlumlordInkGui.CellName());

  let address: String = SlumlordSite.BaseAddress();
  let icon = cell.GetWidgetByPathName(InkGUIHomePage.LinkIconPath()) as inkImage;
  if IsDefined(icon) {
    icon.SetAtlasResource(SlumlordSite.IconAtlas());
    icon.SetTexturePart(SlumlordSite.IconPart());
    icon.RegisterToCallback(n"OnRelease", this, n"OnSlumlordHomeLinkRelease");
    let controller = icon.GetController() as LinkController;
    if IsDefined(controller) {
      controller.SetLinkAddress(address);
    }
  }

  let label = cell.GetWidgetByPathName(InkGUIHomePage.LinkTextPath()) as inkText;
  if IsDefined(label) {
    label.SetText(SlumlordSite.ShortName());
  }
  return true;
}

@if(!ModuleExists("InkGUI"))
@addMethod(WebPage)
public func SlumlordAddInkGuiLink() -> Bool {
  return false;
}

// InkGUI moves the vanilla `panel` into its scroll box: page/linkPanel/<scroll>/scrollArea/content/panel.
// Until it has, there is no such path and this returns null.
@if(ModuleExists("InkGUI"))
@addMethod(WebPage)
private func SlumlordInkGuiPanel() -> wref<inkCompoundWidget> {
  let linkPanel = this.GetChildWidgetByPath(InkGUIHomePage.LinkPanelPath()) as inkCompoundWidget;
  if !IsDefined(linkPanel) {
    return null;
  }
  let i: Int32 = 0;
  while i < linkPanel.GetNumChildren() {
    let scroll = linkPanel.GetWidgetByIndex(i) as inkCompoundWidget;
    if IsDefined(scroll) {
      let content = scroll.GetWidgetByPathName(InkGUIStyle.ScrollContentPath()) as inkCompoundWidget;
      if IsDefined(content) {
        let panel = content.GetWidgetByPathName(n"panel") as inkCompoundWidget;
        if IsDefined(panel) {
          return panel;
        }
      }
    }
    i += 1;
  }
  return null;
}

@if(ModuleExists("InkGUI"))
@addMethod(WebPage)
protected cb func OnSlumlordHomeLinkRelease(evt: ref<inkPointerEvent>) -> Bool {
  if !evt.IsAction(n"click") {
    return false;
  }
  this.m_lastClickedLinkAddress = SlumlordSite.BaseAddress();
  this.CallCustomCallback(n"OnLinkPressed");
  return false;
}
