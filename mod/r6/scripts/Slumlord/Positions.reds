// World positions for property map pins.
// Capture them in game with the SlumlordDebug CET window ("Capture position"), which appends
// ready-to-paste lines to captured_positions.txt in its mod folder. Paste them inside Get().
// A property without a position gets no pin.
module Slumlord

public abstract class SlumlordPositions {

  public static func Get(id: CName) -> Vector4 {
    // PASTE CAPTURED LINES BELOW. Example:
    // if Equals(id, n"wat_kabuki_court") { return new Vector4(-1234.56, 789.01, 12.34, 1.0); }
    if Equals(id, n"wat_kabuki_court") { return new Vector4(-1149.37, 2077.63, 7.78, 1.0); } // Kabuki Shop Booth, yaw -24.4
    if Equals(id, n"wat_bradbury_boreas") { return new Vector4(-1495.08, 1147.58, 18.76, 1.0); } // Bradbury & Boreas, yaw -141.8
    if Equals(id, n"wat_capitan_caliente") { return new Vector4(-1401.48, 1416.63, 18.19, 1.0); } // Capitan Caliente, Ellison St, yaw 85.8
    if Equals(id, n"wat_kabuki_waterfront") { return new Vector4(-1073.04, 1583.93, 2.58, 1.0); } // Kabuki Waterfront, yaw 6.0
    if Equals(id, n"wat_harbor_safehouse") { return new Vector4(-2013.79, 2617.27, 18.13, 1.0); } // Harbor Safehouse, yaw 27.1

    return new Vector4(0.0, 0.0, 0.0, 0.0);
  }

  // W = 1.0 marks a captured position; the fallback above uses W = 0.0.
  public static func Has(id: CName) -> Bool {
    let p = SlumlordPositions.Get(id);
    return p.W > 0.5;
  }
}
