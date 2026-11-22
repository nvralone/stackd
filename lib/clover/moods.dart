// Clover's 20 emotional states and how each one animates.
enum CloverMood {
  happy('Happy', bounce: 1.0, pitch: 1.15),
  proud('Proud', bounce: 0.6, pitch: 1.05, effect: CloverEffect.sparkle),
  dollarEyes('Dollar-sign eyes', bounce: 1.4, pitch: 1.3, effect: CloverEffect.dollar),
  excited('Extremely excited', bounce: 2.2, pitch: 1.45, effect: CloverEffect.marks),
  angry('Angry', shake: 2.0, pitch: 0.85, effect: CloverEffect.anger),
  disappointed('Disappointed', bounce: 0.2, droop: 1, pitch: 0.8, effect: CloverEffect.sigh),
  shocked('Shocked', jump: true, pitch: 1.5, effect: CloverEffect.exclaim),
  panicking('Panicking', shake: 3.0, bounce: 2.0, pitch: 1.6, effect: CloverEffect.sweat),
  crying('Crying', bounce: 0.3, droop: 1, pitch: 1.25, effect: CloverEffect.tears),
  suspicious('Suspicious', tilt: 1, pitch: 0.9, effect: CloverEffect.squint),
  thinking('Thinking', tilt: 1, bounce: 0.3, pitch: 1.0, effect: CloverEffect.dots),
  confused('Confused', tilt: -1, pitch: 1.1, effect: CloverEffect.question),
  sleepy('Sleepy', bounce: 0.15, droop: 1, pitch: 0.75, effect: CloverEffect.zzz),
  bored('Bored', bounce: 0.1, pitch: 0.8, effect: CloverEffect.sigh),
  smug('Smug', tilt: 1, bounce: 0.5, pitch: 0.95, effect: CloverEffect.sparkle),
  begging('Begging', bounce: 1.2, pitch: 1.4, effect: CloverEffect.heart),
  celebrating('Celebrating', bounce: 2.5, jump: true, pitch: 1.5, effect: CloverEffect.confetti),
  determined('Determined', bounce: 0.8, pitch: 1.0, effect: CloverEffect.fire),
  vacation('Vacation mode', bounce: 0.7, tilt: -1, pitch: 1.1, effect: CloverEffect.sun),
  deadInside('Dead-inside', bounce: 0.0, droop: 1, pitch: 0.65, effect: CloverEffect.flat);

  final String label;
  final double bounce, shake, pitch;
  final int tilt, droop;
  final bool jump;
  final CloverEffect effect;
  const CloverMood(this.label,
      {this.bounce = 0.5, this.shake = 0, this.pitch = 1.0, this.tilt = 0, this.droop = 0, this.jump = false,
      this.effect = CloverEffect.none});

  /// Dedicated sprite path from the asset manifest (docs/CLOVER_ASSETS.md). Optional until art exists.
  String get spritePath => 'assets/clover/moods/${name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')}.png';
}

/// Overlay glyph drawn beside the sprite. These are UI effects, not replacements for mood art.
enum CloverEffect { none, sparkle, dollar, marks, anger, sigh, exclaim, sweat, tears, squint, dots, question, zzz, heart, confetti, fire, sun, flat }
