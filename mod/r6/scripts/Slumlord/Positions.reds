// World positions for property map pins.
// Capture them in game with the SlumlordDebug CET window ("Capture position"), which appends
// ready-to-paste lines to captured_positions.txt in its mod folder. Paste them inside Get().
// A property without a position gets no pin.
module Slumlord

public abstract class SlumlordPositions {

  public static func Get(id: CName) -> Vector4 {
    // PASTE CAPTURED LINES BELOW. Example:
    // if Equals(id, n"wat_example_id") { return new Vector4(-1234.56, 789.01, 12.34, 1.0); }
    if Equals(id, n"wat_kabuki_shop_booth") { return new Vector4(-1149.37, 2077.63, 7.78, 1.0); } // Kabuki Shop Booth, yaw -24.4
    if Equals(id, n"wat_bradbury_boreas") { return new Vector4(-1495.08, 1147.58, 18.76, 1.0); } // Bradbury & Boreas, yaw -141.8
    if Equals(id, n"wat_capitan_caliente") { return new Vector4(-1401.48, 1416.63, 18.19, 1.0); } // Capitan Caliente, Ellison St, yaw 85.8
    if Equals(id, n"wat_kabuki_waterfront") { return new Vector4(-1073.04, 1583.93, 2.58, 1.0); } // Kabuki Waterfront, yaw 6.0
    if Equals(id, n"wat_harbor_safehouse") { return new Vector4(-2013.79, 2617.27, 18.13, 1.0); } // Harbor Safehouse, yaw 27.1
    if Equals(id, n"sd_charming_suburban_adu") { return new Vector4(168.25, -1836.09, -10.27, 1.0); } // Charming Suburban ADU, yaw -126.8
    if Equals(id, n"sd_dam_bungalow") { return new Vector4(645.06, -2150.74, 39.22, 1.0); } // Dam Bungalow, yaw -124.9
    if Equals(id, n"sd_chooh2_carnitas_st") { return new Vector4(-137.61, -1972.82, 5.87, 1.0); } // Chooh2 Carnitas St, yaw 20.2
    if Equals(id, n"sd_manufactory_food_stall") { return new Vector4(-1024.70, -1569.34, 25.70, 1.0); } // Manufactory Food Stall, yaw -123.6
    if Equals(id, n"sd_mission_st_garages") { return new Vector4(-887.15, -1119.54, 11.80, 1.0); } // Mission St Garages, yaw -119.1

    return new Vector4(0.0, 0.0, 0.0, 0.0);
  }

  // W = 1.0 marks a captured position; the fallback above uses W = 0.0.
  public static func Has(id: CName) -> Bool {
    let p = SlumlordPositions.Get(id);
    return p.W > 0.5;
  }
}
