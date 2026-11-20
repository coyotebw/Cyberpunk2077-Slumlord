// Positional voice for NPC lines: Audioware's spatial emitters (the voice comes from the speaker, with distance
// and direction). V's own lines, and every line when Audioware is missing, play flat as before.
module Slumlord

@if(ModuleExists("Audioware"))
import Audioware.*

// Registers the speaker as a voice emitter. Call as soon as the NPC exists, so the first line is already
// positional (registering on the first line could fall back to flat playback). Full volume within 4 m,
// fading out to 45 m; no occlusion, so a car or a pillar doesn't swallow the line.
@if(ModuleExists("Audioware"))
public func SlumlordVoiceReady(game: GameInstance, speaker: ref<GameObject>) -> Bool {
  if !IsDefined(speaker) || speaker.IsPlayer() { return false; }
  let ext = GameInstance.GetAudioSystemExt(game);
  let id = speaker.GetEntityID();
  if ext.IsRegisteredEmitter(id, n"slumlord_voice") { return true; }
  let distances = new EmitterDistances();
  distances.min = 4.0;
  distances.max = 45.0;
  let settings = new EmitterSettings();
  settings.distances = distances;
  settings.enableSpatialization = true;
  settings.persistUntilSoundsFinish = true;
  settings.enableOcclusion = false;
  ext.RegisterEmitter(id, n"slumlord_voice", n"Slumlord", settings);
  return ext.IsRegisteredEmitter(id, n"slumlord_voice");
}

@if(!ModuleExists("Audioware"))
public func SlumlordVoiceReady(game: GameInstance, speaker: ref<GameObject>) -> Bool { return false; }

@if(ModuleExists("Audioware"))
public func SlumlordVoice(game: GameInstance, audio: CName, speaker: ref<GameObject>) -> Void {
  if IsDefined(speaker) && !speaker.IsPlayer() {
    if SlumlordVoiceReady(game, speaker) {
      GameInstance.GetAudioSystemExt(game).PlayOnEmitter(audio, speaker.GetEntityID(), n"slumlord_voice");
      return;
    }
    SlumlordUi.Log("Voice: no emitter on " + EntityID.ToDebugString(speaker.GetEntityID()) + ", playing " + NameToString(audio) + " flat");
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
