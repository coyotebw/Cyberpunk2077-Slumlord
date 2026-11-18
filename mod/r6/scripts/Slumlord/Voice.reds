// Positional voice for NPC lines: Audioware's spatial emitters (the voice comes from the speaker, with distance
// and direction). V's own lines, and every line when Audioware is missing, play flat as before.
module Slumlord

@if(ModuleExists("Audioware"))
import Audioware.*

@if(ModuleExists("Audioware"))
public func SlumlordVoice(game: GameInstance, audio: CName, speaker: ref<GameObject>) -> Void {
  if IsDefined(speaker) && !speaker.IsPlayer() {
    let ext = GameInstance.GetAudioSystemExt(game);
    let id = speaker.GetEntityID();
    if !ext.IsRegisteredEmitter(id, n"slumlord_voice") {
      ext.RegisterEmitter(id, n"slumlord_voice", n"Slumlord");
    }
    if ext.IsRegisteredEmitter(id, n"slumlord_voice") {
      ext.PlayOnEmitter(audio, id, n"slumlord_voice");
      return;
    }
  }
  GameInstance.GetAudioSystem(game).Play(audio);
}

@if(!ModuleExists("Audioware"))
public func SlumlordVoice(game: GameInstance, audio: CName, speaker: ref<GameObject>) -> Void {
  GameInstance.GetAudioSystem(game).Play(audio);
}

@if(ModuleExists("Audioware"))
public func SlumlordForgetVoice(game: GameInstance, id: EntityID) -> Void {
  let ext = GameInstance.GetAudioSystemExt(game);
  if ext.IsRegisteredEmitter(id, n"slumlord_voice") {
    ext.UnregisterEmitter(id, n"slumlord_voice");
  }
}

@if(!ModuleExists("Audioware"))
public func SlumlordForgetVoice(game: GameInstance, id: EntityID) -> Void {}
