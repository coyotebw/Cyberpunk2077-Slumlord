// Resident names, for flavour in texts (Andrew's list: project doc "resident-names", 2026-11-18).
// Names are not tracked per unit. Karl Mendes lives at the Harbor Safehouse (Million Dollar Baby), so
// random picks for other properties skip him.
module Slumlord

public abstract class SlumlordNames {

  public static func Residents() -> array<String> {
    return [
      "Karl Mendes", "Silas Pedersen", "Freyr Tarasov", "Eira Orion", "Lina Gorrea", "Wizzy Lizzy",
      "Isabella Li", "Freyja Rivera", "Nano Diawara", "Heebo Slungis", "Francis Zephyr", "Claire Andersen",
      "Gustav Vorobev", "Sleve McDichael", "Anatoli Smorin", "Hanna Quantum", "Yuuto Vanguard", "Ella Woodard",
      "Bobson Dugnutt", "Link Nielson", "Katya Toure", "Decatholac Mango", "Kora Skyler", "Evelyn Evans",
      "Axel Lester", "Kaori Diallo", "Todd Bonzalez", "Olivia Sanchez", "Labubu James", "Blaze Richardson",
      "Logjammer D'Baggagecling", "Elizabeth Torres", "Jeeves Lin", "Hingle McCringleberry", "Aiden Bianchi",
      "Oscar Reyes", "Kimchi Quart", "Brendan Cipher", "Diego Poulsen", "John Martin", "Dexter Quyen",
      "Tyroil Smoochie-Wallace", "Ryan Banks", "Fartrell Cluggins", "Nyra Lang", "L'Carpetron Dookmarriot",
      "Akiko Nakamura", "Benedict Cucumberpatch", "Okonkwo Umuofia", "Jernau Gurgeh", "Ozamataz Buckshank"
    ];
  }

  // Index 0 is Karl: random picks use 1..n-1.
  public static func RandomIndex(roll: Float) -> Int32 {
    let names = SlumlordNames.Residents();
    let count = ArraySize(names);
    return 1 + Min(count - 2, FloorF(roll * Cast<Float>(count - 1)));
  }

  public static func Get(index: Int32) -> String {
    let names = SlumlordNames.Residents();
    if index < 0 || index >= ArraySize(names) { return "A tenant"; }
    return names[index];
  }
}
