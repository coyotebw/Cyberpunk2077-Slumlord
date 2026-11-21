// "Slumlord properties" row in the world map's filter list: shows or hides Slumlord's property pins (listings,
// holdings, rent-ready, trouble) on the full map. Quest pins (motel, Harbor Safehouse) are not affected, nor is
// the minimap. The choice is saved per save game (fact slumlord_map_hidden). Mod Settings' "Property pins" still
// turns the pins off everywhere.
//
// The row is a TweakDB filter group made at startup by TweakXL (SlumlordMapFilterTweak): a clone of the first
// vanilla group, with no mappin variants of its own, appended to WorldMap.WorldMapCustomFiltersList. Its toggle is
// handled here, never by the game's filter bits, so the cloned filter type is never switched.
// Same approach as Marmur Bank's branch/ATM filter (MarmurBankMapFilter.reds); every hook below acts only on
// Slumlord's own row and pins and passes everything else through, so the two filters coexist.
// Visibility: "All" quick filter = shown; custom filters = this row's toggle; any other quick filter = hidden.
module Slumlord

public class SlumlordMapFilterTweak extends ScriptableTweak {
  protected cb func OnApply() -> Void {
    let listId = t"WorldMap.WorldMapCustomFiltersList";
    let ours = SlumlordMapFilter.GroupId();
    let list = FromVariant<array<TweakDBID>>(TweakDBInterface.GetFlat(listId + t".list"));
    if ArraySize(list) == 0 { return; }
    if !ArrayContains(list, ours) {
      if !IsDefined(TweakDBInterface.GetRecord(ours)) {
        TweakDBManager.CloneRecord(n"WorldMap.SlumlordFilterGroup", list[0]);
        let none: array<TweakDBID>;
        TweakDBManager.SetFlat(n"WorldMap.SlumlordFilterGroup.mappins", ToVariant(none));
        TweakDBManager.SetFlat(n"WorldMap.SlumlordFilterGroup.filterName", ToVariant(n"Slumlord properties"));
        TweakDBManager.UpdateRecord(ours);
      }
      ArrayPush(list, ours);
      TweakDBManager.SetFlat(listId + t".list", ToVariant(list));
      TweakDBManager.UpdateRecord(listId);
    }
  }
}

public abstract class SlumlordMapFilter {
  public static func GroupId() -> TweakDBID { return t"WorldMap.SlumlordFilterGroup"; }
  public static func Fact() -> CName { return n"slumlord_map_hidden"; }

  public static func IsEnabled() -> Bool {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    return !IsDefined(quests) || quests.GetFact(SlumlordMapFilter.Fact()) != 1;
  }

  public static func Toggle() -> Void {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if IsDefined(quests) { quests.SetFact(SlumlordMapFilter.Fact(), SlumlordMapFilter.IsEnabled() ? 1 : 0); }
  }

  public static func IsGroup(group: wref<MappinUIFilterGroup_Record>) -> Bool {
    return IsDefined(group) && group.GetID() == SlumlordMapFilter.GroupId();
  }

  public static func IsOurs(mappin: wref<IMappin>) -> Bool {
    return IsDefined(mappin) && IsDefined(mappin.GetScriptData() as SlumlordPinData);
  }
}

// ---- the open map, and our pins' map controllers (to refresh them when the row is toggled)

@addField(MappinSystem)
private let slumlordMapMenu: wref<WorldMapMenuGameController>;

@addField(MappinSystem)
private let slumlordMapControllers: array<wref<BaseWorldMapMappinController>>;

@addMethod(MappinSystem)
public final func SlumlordAttachMap(menu: ref<WorldMapMenuGameController>) -> Void {
  this.slumlordMapMenu = menu;
}

@addMethod(MappinSystem)
public final func SlumlordDetachMap(menu: ref<WorldMapMenuGameController>) -> Void {
  if this.slumlordMapMenu == menu {
    this.slumlordMapMenu = null;
    ArrayClear(this.slumlordMapControllers);
  }
}

@addMethod(MappinSystem)
public final func SlumlordMapLayerVisible() -> Bool {
  if !IsDefined(this.slumlordMapMenu) { return SlumlordMapFilter.IsEnabled(); }
  let mode = this.slumlordMapMenu.GetQuickFilter();
  if Equals(mode, gamedataWorldMapFilter.CustomFilter) { return SlumlordMapFilter.IsEnabled(); }
  return Equals(mode, gamedataWorldMapFilter.NoFilter);
}

@addMethod(MappinSystem)
public final func SlumlordRegisterMapController(controller: ref<BaseWorldMapMappinController>) -> Void {
  let i = ArraySize(this.slumlordMapControllers) - 1;
  while i >= 0 {
    if !IsDefined(this.slumlordMapControllers[i]) {
      ArrayErase(this.slumlordMapControllers, i);
    } else {
      if this.slumlordMapControllers[i] == controller { return; }
    }
    i -= 1;
  }
  ArrayPush(this.slumlordMapControllers, controller);
}

@addMethod(MappinSystem)
public final func SlumlordRefreshMapLayer() -> Void {
  let i = ArraySize(this.slumlordMapControllers) - 1;
  while i >= 0 {
    if IsDefined(this.slumlordMapControllers[i]) {
      this.slumlordMapControllers[i].SlumlordRefreshMapPin();
    } else {
      ArrayErase(this.slumlordMapControllers, i);
    }
    i -= 1;
  }
}

// ---- the filter row

@addMethod(WorldMapFiltersListItem)
public final func SlumlordIsFilter() -> Bool {
  return SlumlordMapFilter.IsGroup(this.m_filterGroup);
}

@wrapMethod(WorldMapFiltersListItem)
public func SetFilterGroup(filterGroup: wref<MappinUIFilterGroup_Record>) -> Void {
  wrappedMethod(filterGroup);
  if this.SlumlordIsFilter() {
    inkTextRef.SetText(this.m_filterName, "SLUMLORD PROPERTIES");
  }
}

@wrapMethod(WorldMapFiltersListItem)
public func EnableFilter(enable: Bool) -> Void {
  if this.SlumlordIsFilter() { enable = SlumlordMapFilter.IsEnabled(); }
  wrappedMethod(enable);
}

// ---- the map menu

@wrapMethod(WorldMapMenuGameController)
protected cb func OnInitialize() -> Bool {
  let result = wrappedMethod();
  if IsDefined(this.m_mappinSystem) { this.m_mappinSystem.SlumlordAttachMap(this); }
  return result;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnUninitialize() -> Bool {
  if IsDefined(this.m_mappinSystem) { this.m_mappinSystem.SlumlordDetachMap(this); }
  return wrappedMethod();
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnQuickFilterChanged(group: wref<MappinUIFilterGroup_Record>) -> Bool {
  let result = wrappedMethod(group);
  if IsDefined(this.m_mappinSystem) { this.m_mappinSystem.SlumlordRefreshMapLayer(); }
  return result;
}

// Our row is set up here, not by the game: its state comes from the fact, not the game's filter bits.
@wrapMethod(WorldMapMenuGameController)
protected cb func OnFilterListItemSpawned(filterWidget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
  let group = userData as MappinUIFilterGroup_Record;
  if !SlumlordMapFilter.IsGroup(group) { return wrappedMethod(filterWidget, userData); }
  if !IsDefined(filterWidget) || this.m_spawnedCustomFilterIndex < 0
    || this.m_spawnedCustomFilterIndex >= ArraySize(this.m_customFiltersList) { return false; }
  let filter = filterWidget.GetController() as WorldMapFiltersListItem;
  if !IsDefined(filter) { return false; }
  filter.SetFilterGroup(group);
  filter.SetFilterState(n"Default");
  filter.EnableFilter(SlumlordMapFilter.IsEnabled());
  filterWidget.RegisterToCallback(n"OnRelease", this, n"OnFilterSwitched");
  this.m_customFiltersList[this.m_spawnedCustomFilterIndex] = filter;
  this.m_spawnedCustomFilterIndex += 1;
  return true;
}

@addMethod(WorldMapMenuGameController)
private final func SlumlordToggleFilter(filter: ref<WorldMapFiltersListItem>) -> Void {
  SlumlordMapFilter.Toggle();
  filter.EnableFilter(SlumlordMapFilter.IsEnabled());
  this.PlaySound(n"Button", n"OnPress");
  if IsDefined(this.m_mappinSystem) { this.m_mappinSystem.SlumlordRefreshMapLayer(); }
  this.OnCustomFilterChanged();
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnFilterSwitched(evt: ref<inkPointerEvent>) -> Bool {
  if IsDefined(evt) && (evt.IsAction(n"click") || evt.IsAction(n"tap")) && this.canChangeCustomFilter {
    let target = evt.GetTarget();
    if IsDefined(target) {
      let filter = target.GetController() as WorldMapFiltersListItem;
      if IsDefined(filter) && filter.SlumlordIsFilter() {
        this.SlumlordToggleFilter(filter);
        return true;
      }
    }
  }
  return wrappedMethod(evt);
}

// Controller (d-pad) toggle on our row.
@wrapMethod(WorldMapMenuGameController)
private final func NavigateCustomFilters(option: ECustomFilterDPadNavigationOption) -> Void {
  if Equals(option, ECustomFilterDPadNavigationOption.Toggle)
    && this.m_currentCustomFilterIndex >= 0 && this.m_currentCustomFilterIndex < ArraySize(this.m_customFiltersList) {
    let filter = this.m_customFiltersList[this.m_currentCustomFilterIndex];
    if IsDefined(filter) && filter.SlumlordIsFilter() {
      this.SlumlordToggleFilter(filter);
      filter.SetFilterState(n"Hover");
      return;
    }
  }
  wrappedMethod(option);
}

// ---- our pins on the map

@wrapMethod(BaseWorldMapMappinController)
protected cb func OnIntro() -> Bool {
  let result = wrappedMethod();
  if SlumlordMapFilter.IsOurs(this.GetMappin()) {
    GameInstance.GetMappinSystem(GetGameInstance()).SlumlordRegisterMapController(this);
  }
  return result;
}

@addMethod(BaseWorldMapMappinController)
public final func SlumlordRefreshMapPin() -> Void {
  if IsDefined(this.GetRootWidget()) && SlumlordMapFilter.IsOurs(this.GetMappin()) {
    this.OnFiltersChanged();
  }
}

@wrapMethod(BaseWorldMapMappinController)
protected cb func OnFiltersChanged() -> Bool {
  if !SlumlordMapFilter.IsOurs(this.GetMappin()) { return wrappedMethod(); }
  let hadFilter = this.hasCustomFilter;
  let wasIn = this.inCustomFilter;
  let visible = GameInstance.GetMappinSystem(GetGameInstance()).SlumlordMapLayerVisible();
  this.hasCustomFilter = true;
  this.inCustomFilter = visible;
  let result = wrappedMethod();
  this.hasCustomFilter = hadFilter;
  this.inCustomFilter = wasIn;
  if !visible {
    this.StopFadeAnimation();
    this.GetRootWidget().SetOpacity(0.0);
    this.GetRootWidget().SetInteractive(false);
    this.isVisibleInFilterAndZoom = false;
  }
  return result;
}
