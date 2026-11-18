// Map pins in the design system's MapPin style (Slumlord UI Design System, components/MapPin):
// owned properties show a diamond in their rank colour and letter, rent ready a gold "$",
// trouble a red "!", listings a dashed cyan "+". Textures: slumlord\gui\slumlord_pins.inkatlas
// (tools/icon/make_pins.py). Each Slumlord pin carries a SlumlordPinData naming its atlas part;
// the game's own pin controllers draw the variant icon first, then these wraps swap in ours.
module Slumlord

public class SlumlordPinData extends MappinScriptData {
  public let part: CName;
}

public abstract class SlumlordPins {
  public static func Atlas() -> ResRef { return r"slumlord\\gui\\slumlord_pins.inkatlas"; }

  // Priority as in the design system: trouble, then rent, then owned. Unowned: listing.
  public static func PartFor(state: ref<SlumlordPropertyState>) -> CName {
    if !IsDefined(state) || !state.owned {
      return n"slumlord_pin_listing";
    }
    if state.uncollected > 0 {
      return n"slumlord_pin_rent";
    }
    return StringToName("slumlord_pin_" + StrLower(SlumlordEconomy.RankLetter(state.rank)));
  }

  public static func Data(state: ref<SlumlordPropertyState>) -> ref<SlumlordPinData> {
    let data = new SlumlordPinData();
    data.part = SlumlordPins.PartFor(state);
    return data;
  }

  public static func Restyle(mappin: wref<IMappin>, icon: inkImageRef) -> Void {
    if !IsDefined(mappin) { return; }
    let data = mappin.GetScriptData() as SlumlordPinData;
    if !IsDefined(data) { return; }
    inkImageRef.SetAtlasResource(icon, SlumlordPins.Atlas());
    inkImageRef.SetTexturePart(icon, data.part);
    let widget = inkWidgetRef.Get(icon);
    if IsDefined(widget) {
      widget.UnbindProperty(n"tintColor");   // the variant's colour would tint our texture
      widget.SetTintColor(new HDRColor(1.0, 1.0, 1.0, 1.0));
    }
  }
}

// World map.
@wrapMethod(BaseWorldMapMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  SlumlordPins.Restyle(this.m_mappin, this.iconWidget);
}

// Minimap.
@wrapMethod(MinimapPOIMappinController)
protected final func UpdateIcon() -> Void {
  wrappedMethod();
  SlumlordPins.Restyle(this.m_mappin, this.iconWidget);
}

// In the world (HUD).
@wrapMethod(QuestMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  SlumlordPins.Restyle(this.m_mappin, this.iconWidget);
}

@wrapMethod(GameplayMappinController)
private func UpdateIcon() -> Void {
  wrappedMethod();
  SlumlordPins.Restyle(this.m_mappin, this.iconWidget);
}
