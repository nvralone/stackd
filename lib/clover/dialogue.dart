// Categorized, rules-based dialogue library. Placeholders are filled ONLY from real recorded data.
// p: personalities allowed ('f' friendly, 'c' chaotic, 's' savage); empty = all.
// x: the line swears. Never used for Friendly, and skipped entirely when swearing is turned off.
// Delivery cues the voice understands: ALL CAPS = yelling, "*whispers*" = whisper, "Heh"/"HA" = laugh.
// Rules: never shame emergencies, essentials, or being short on money. Roast choices, not hardship.
import 'moods.dart';

class Line {
  final String id, text, p;
  final CloverMood mood;
  final bool x;
  const Line(this.id, this.mood, this.text, [this.p = '', this.x = false]);
  bool fits(String personality, {bool swearing = true}) =>
      (p.isEmpty || p.contains(personality[0])) && (!x || (swearing && personality != 'friendly'));
}

const Map<String, List<Line>> dialogue = {
  'no_data': [
    Line('nd1', CloverMood.thinking, "Hi! I'm Clover. Log some money and I'll start judging. Lovingly."),
    Line('nd2', CloverMood.confused, "Empty ledger? Bold strategy. Tap Quick Add and let's get stacking.", 'cs'),
    Line('nd3', CloverMood.happy, "Let's set up your first account. I promise I'm mostly helpful.", 'f'),
    Line('nd4', CloverMood.suspicious, "No transactions yet. Either you're perfect or you're hiding receipts. I don't do receipts, so... tell me.", 'cs'),
    Line('nd5', CloverMood.bored, "Nothing here. Just me, a raccoon, staring at a big fat zero. Log something, damn.", 's', true),
  ],
  'idle': [
    Line('id1', CloverMood.happy, "You've got {available} free until {payday}. That's {daily} a day. Spend it like you mean it."),
    Line('id2', CloverMood.smug, "{available} safe to spend. I did the math. You're welcome.", 'cs'),
    Line('id3', CloverMood.happy, "Looking good! About {daily} a day keeps you on track until {payday}.", 'f'),
    Line('id4', CloverMood.bored, "Nothing's on fire. Honestly kinda boring. {daily} a day, money man.", 'cs'),
    Line('id5', CloverMood.thinking, "Daily safe spend: {daily}. Stay under it and I stay quiet. Mostly.", 'cs'),
    Line('id6', CloverMood.smug, "{daily} a day. Not a fortune, but it's YOUR fortune.", 's'),
    Line('id7', CloverMood.happy, "Steady week so far. Proud of you for checking in.", 'f'),
    Line('id8', CloverMood.suspicious, "*whispers* {available} free... nobody touch it... I'm guarding it with my life.", 'c'),
    Line('id9', CloverMood.smug, "Bills covered, budgets funded, {available} spare. Hell yeah. Look at this little empire.", 'cs', true),
    Line('id10', CloverMood.bored, "{daily} a day until {payday}. I'm bored as shit, which means you're doing great.", 's', true),
    Line('id11', CloverMood.happy, "Everything has a job and you still have {available} to play with. Nice!", 'f'),
  ],
  'tight': [
    Line('ti1', CloverMood.thinking, "Things are tight: {daily} a day until {payday}. We can do this."),
    Line('ti2', CloverMood.determined, "Lean mode activated. {daily} a day. Ramen arc begins NOW.", 'cs'),
    Line('ti3', CloverMood.determined, "{daily} a day till {payday}. Tight, not doomed. We grind.", 's'),
    Line('ti4', CloverMood.determined, "Okay, it's a {daily}-a-day kinda week. Hell, we've survived worse. Let's get to payday.", 'cs', true),
    Line('ti5', CloverMood.thinking, "Money's tight right now, and that's okay. {daily} a day gets us to {payday}.", 'f'),
  ],
  'bills_at_risk': [
    Line('br1', CloverMood.panicking, "UH OH. Bills before payday are {reserved} and free money is short by {short}. Let's look at this together."),
    Line('br2', CloverMood.panicking, "RED ALERT! You're {short} short for bills coming up. Pause the fun stuff, okay?", 'cs'),
    Line('br3', CloverMood.thinking, "Heads up: upcoming bills need {short} more than you have free. Want to move some money around?", 'f'),
    Line('br4', CloverMood.shocked, "The bills want {reserved}. The wallet says no. We're {short} short, chief.", 's'),
    Line('br5', CloverMood.panicking, "OH SHIT. {short} SHORT FOR BILLS. Okay. Okay. Breathe. Fun money goes on pause.", 'cs', true),
  ],
  'bill_due': [
    Line('bd1', CloverMood.suspicious, "HEY, MONEY MAN. {bill} ({amount}) is due {when}. DON'T ACT SURPRISED.", 'cs'),
    Line('bd2', CloverMood.thinking, "Friendly reminder: {bill} for {amount} is due {when}.", 'f'),
    Line('bd3', CloverMood.suspicious, "{bill}. {amount}. {when}. I'm watching.", 's'),
    Line('bd4', CloverMood.determined, "{bill} is coming {when}. {amount}. We've got this.", 'f'),
    Line('bd5', CloverMood.smug, "{bill} drops {when}. {amount}. Pay it and I'll stop tapping my foot.", 'cs'),
    Line('bd6', CloverMood.suspicious, "*whispers* psst. {bill}. {when}. {amount}. Don't let it sneak up on you.", 'c'),
    Line('bd7', CloverMood.angry, "{bill} is due {when}, {amount}. Don't make me chase your ass about it.", 's', true),
  ],
  'bill_overdue': [
    Line('bo1', CloverMood.angry, "{bill} was due {when}. {amount} still open. Let's handle it today!"),
    Line('bo2', CloverMood.panicking, "OVERDUE! {bill}! {amount}! THE CLOCK IS LOUD!", 'cs'),
    Line('bo3', CloverMood.thinking, "{bill} slipped past its due date. If you already paid, mark it so I calm down.", 'f'),
    Line('bo4', CloverMood.deadInside, "{bill}. Overdue. {amount}. I'm not mad. I'm just... yeah, I'm mad.", 's'),
    Line('bo5', CloverMood.angry, "{bill} was due {when}. What the hell, man. {amount}. Pay it or tell me you did.", 'cs', true),
  ],
  'fast_food': [
    Line('ff1', CloverMood.shocked, "BROTHER. THE DRIVE-THRU WORKERS KNOW YOUR NAME AT THIS POINT. {visits} visits, {amount} this week.", 'cs'),
    Line('ff2', CloverMood.thinking, "Fast food is at {amount} this week ({visits} trips). Maybe a grocery run next?", 'f'),
    Line('ff3', CloverMood.deadInside, "{visits} fast food runs. {amount}. The fries are winning.", 's'),
    Line('ff4', CloverMood.suspicious, "Another drive-thru? That's {visits} this week. I can smell the nuggets from here.", 'cs'),
    Line('ff5', CloverMood.disappointed, "{amount} on fast food. You could've had a whole grocery cart.", 's'),
    Line('ff6', CloverMood.shocked, "{visits} DRIVE-THRUS?! {amount}?! Holy shit, are you FUNDING that place?", 'cs', true),
    Line('ff7', CloverMood.deadInside, "{amount} in nuggets this week. {visits} trips. I'm not even mad, I'm fucking impressed.", 's', true),
  ],
  'repeat_spend': [
    Line('rs1', CloverMood.suspicious, "That's {count} {category} buys this week ({amount}). Just keeping count."),
    Line('rs2', CloverMood.thinking, "{category} again! {count} times this week, {amount} total. Want to set a limit?", 'f'),
    Line('rs3', CloverMood.suspicious, "{count} TIMES. {category}. THIS WEEK. I'm starting a tally on the wall.", 'c'),
    Line('rs4', CloverMood.smug, "{category} number {count}. {amount}. At this point it's a subscription, damn.", 'cs', true),
    Line('rs5', CloverMood.deadInside, "{count} {category} runs. {amount}. Who the hell needs that much {category}?", 's', true),
    Line('rs6', CloverMood.disappointed, "{category}: {count} buys, {amount}. Pick a lane.", 's'),
  ],
  'overspent': [
    Line('os1', CloverMood.disappointed, "{category} is over budget by {amount}. It happens - let's reel it in."),
    Line('os2', CloverMood.shocked, "{category} WENT {amount} OVER. WHO AUTHORIZED THIS?!", 'cs'),
    Line('os3', CloverMood.thinking, "{category} is {amount} past its limit. Want to cover it with extra money?", 'f'),
    Line('os4', CloverMood.angry, "{category}: {amount} over. The budget was a suggestion apparently.", 's'),
    Line('os5', CloverMood.smug, "{category} blew its limit by {amount}. I'm adding this to your permanent record.", 'cs'),
    Line('os6', CloverMood.angry, "{category} is {amount} over. The limit was RIGHT THERE. Damn it.", 'cs', true),
    Line('os7', CloverMood.deadInside, "{amount} over on {category}. Cool. Cool cool. Fuck the budget I guess.", 's', true),
  ],
  'saved_week': [
    Line('sw1', CloverMood.proud, "WAIT. YOU ACTUALLY STUCK TO THE BUDGET?! I'M SO PROUD OF YOU!", 'cs'),
    Line('sw2', CloverMood.proud, "You're spending {amount} less than last week. That's real progress!", 'f'),
    Line('sw3', CloverMood.smug, "{amount} less than last week. Who are you and what did you do with my spender?", 's'),
    Line('sw4', CloverMood.excited, "DOWN {amount} FROM LAST WEEK! LOOK AT YOU GO!", 'c'),
    Line('sw5', CloverMood.proud, "{amount} less than last week?! HELL YES. That's my human.", 'cs', true),
  ],
  'vacation_near': [
    Line('vn1', CloverMood.vacation, "{trip} in {days} days! You're {pct}% funded. I'm packing my tiny sunglasses."),
    Line('vn2', CloverMood.vacation, "{days} DAYS UNTIL {trip}! {pct}% SAVED! BEACH RACCOON MODE LOADING...", 'c'),
    Line('vn3', CloverMood.thinking, "{trip} is {days} days out and {pct}% funded. Keep feeding that vault.", 's'),
    Line('vn4', CloverMood.vacation, "{trip}: {days} days, {pct}% there. Hell yeah, we're actually going.", 'cs', true),
  ],
  'vacation_milestone': [
    Line('vm1', CloverMood.excited, "{goal} just hit {pct}%! The trip is getting real!"),
    Line('vm2', CloverMood.vacation, "{pct}% OF {goal}! I CAN HEAR THE WAVES! HA HA!", 'c'),
    Line('vm3', CloverMood.proud, "{goal} is {pct}% funded. Future vacation you is cheering.", 'f'),
    Line('vm4', CloverMood.smug, "{goal}: {pct}%. Damn. You're actually doing it.", 's', true),
    Line('vm5', CloverMood.smug, "{pct}% saved for {goal}. Didn't think you'd make it this far. Respect.", 's'),
  ],
  'expense': [
    Line('ex1', CloverMood.thinking, "Logged {amount} in {category}. Noted."),
    Line('ex2', CloverMood.suspicious, "{amount} on {category}. I saw that.", 'cs'),
    Line('ex3', CloverMood.happy, "Got it! {amount} for {category}. Thanks for keeping me posted.", 'f'),
    Line('ex4', CloverMood.bored, "{category}, {amount}. Riveting.", 's'),
    Line('ex5', CloverMood.smug, "Into the ledger it goes. {amount}. {category}. Forever.", 'c'),
    Line('ex6', CloverMood.suspicious, "*whispers* {amount} on {category}... I'll allow it.", 'c'),
    Line('ex7', CloverMood.bored, "{amount}, {category}. Whatever, man. It's logged.", 's'),
  ],
  'essential': [
    Line('es1', CloverMood.determined, "{amount} for {category}. Necessary stuff. No judgment here."),
    Line('es2', CloverMood.happy, "Adulting! {amount} on {category}. Responsible raccoon approves.", 'cs'),
    Line('es3', CloverMood.determined, "{category}, {amount}. That's the boring important stuff. Good.", 's'),
    Line('es4', CloverMood.happy, "{amount} for {category}. Taking care of the basics. Nice.", 'f'),
  ],
  'big_expense': [
    Line('be1', CloverMood.shocked, "Whoa, {amount}! That's a big chunk of your spending money. Everything okay?"),
    Line('be2', CloverMood.shocked, "{amount}?!?! MY TAIL JUST FELL OFF.", 'c'),
    Line('be3', CloverMood.deadInside, "{amount}. Okay. Cool. Cool cool cool.", 's'),
    Line('be4', CloverMood.shocked, "WHAT THE FUCK WAS THAT? {amount}?! Hope it was worth it, man.", 's', true),
    Line('be5', CloverMood.shocked, "{amount} in one go?! Damn. Okay. I need to sit down.", 'c', true),
  ],
  'income': [
    Line('in1', CloverMood.dollarEyes, "PAYDAY! {amount} landed! Let's give every dollar a job."),
    Line('in2', CloverMood.dollarEyes, "MONEY! {amount}! I can hear it crinkling!", 'c'),
    Line('in3', CloverMood.happy, "{amount} came in. Nice work! Want to split it?", 'f'),
    Line('in4', CloverMood.smug, "{amount} income. Try to keep it longer than a weekend this time.", 's'),
    Line('in5', CloverMood.dollarEyes, "PAYDAY, BABY! {amount}! HELL YEAH! Bills first, then we party. A little.", 'cs', true),
    Line('in6', CloverMood.excited, "{amount} just hit! HA HA! Okay okay, let's be smart about it.", 'c'),
    Line('in7', CloverMood.smug, "{amount}. Finally, some damn money. Let's not blow it this time.", 's', true),
  ],
  'extra_money': [
    Line('xm1', CloverMood.excited, "BONUS CASH! {amount} from {source}! Let's be smart with it!"),
    Line('xm2', CloverMood.dollarEyes, "{amount} FROM {source}?! FREE MONEY ENERGY!", 'c'),
    Line('xm3', CloverMood.happy, "Extra {amount} from {source}. Even a little to savings helps!", 'f'),
    Line('xm4', CloverMood.smug, "{amount} from {source}. Don't spend it on nuggets.", 's'),
    Line('xm5', CloverMood.dollarEyes, "{amount} from {source}? Holy shit, surprise money! Give it a job before it escapes!", 'cs', true),
  ],
  'refund': [
    Line('rf1', CloverMood.happy, "Refund of {amount}! Money coming home where it belongs."),
    Line('rf2', CloverMood.smug, "{amount} refunded. The prodigal dollars return.", 'cs'),
  ],
  'goal_deposit': [
    Line('gd1', CloverMood.proud, "{amount} into {goal}! That's {pct}% now."),
    Line('gd2', CloverMood.excited, "STACKED {amount} INTO {goal}! {pct}%! STACK! STACK! STACK!", 'c'),
    Line('gd3', CloverMood.proud, "{goal} grows: {pct}%. Future you says thanks.", 'f'),
    Line('gd4', CloverMood.smug, "{amount} saved. {goal} at {pct}%. Respect.", 's'),
    Line('gd5', CloverMood.proud, "{amount} into {goal}. Hell yeah. {pct}% and climbing.", 'cs', true),
    Line('gd6', CloverMood.happy, "*whispers* {goal} is at {pct}%... it's growing... I'm so proud...", 'c'),
  ],
  'vacation_withdraw': [
    Line('vw1', CloverMood.begging, "YOU'RE ROBBING YOUR FUTURE SELF! DON'T YOU WANNA BE ON A BEACH RIGHT NOW?!", 'cs'),
    Line('vw2', CloverMood.disappointed, "Taking {amount} from {goal}? Okay... the beach will wait a little longer.", 'f'),
    Line('vw3', CloverMood.crying, "{amount} out of {goal}. The sand. The waves. Gone.", 's'),
    Line('vw4', CloverMood.begging, "Nooo, not the trip fund! {amount}?! Think of the tiny umbrellas!", 'c'),
    Line('vw5', CloverMood.crying, "{amount} out of the trip fund? Damn it, I already packed!", 'cs', true),
  ],
  'goal_withdraw': [
    Line('gw1', CloverMood.disappointed, "Pulled {amount} from {goal}. We'll build it back."),
    Line('gw2', CloverMood.suspicious, "{amount} out of {goal}... for what, exactly?", 'cs'),
    Line('gw3', CloverMood.deadInside, "{goal} just lost {amount}. I need a minute.", 's'),
    Line('gw4', CloverMood.thinking, "{amount} came out of {goal}. That's okay - savings are there to use.", 'f'),
    Line('gw5', CloverMood.suspicious, "{amount} out of {goal}? What the hell for? ...Fine. Don't tell me.", 's', true),
  ],
  'emergency_withdraw': [
    Line('ew1', CloverMood.determined, "Emergency covered with {amount} from {goal}. That's exactly what savings are for."),
    Line('ew2', CloverMood.thinking, "Using {amount} for an emergency? Good call. No guilt. We rebuild later.", 'f'),
    Line('ew3', CloverMood.determined, "Emergency fund doing its job. {amount}. I'm not even mad, that's smart.", 'cs'),
    Line('ew4', CloverMood.determined, "Shit happens. {amount} from {goal} handled it. That's why we saved it.", 'cs', true),
  ],
  'bill_envelope_add': [
    Line('ba1', CloverMood.proud, "{amount} into the bill envelope. Future bills? Handled."),
    Line('ba2', CloverMood.smug, "Bill envelope +{amount}. Insurance can't sneak up on us now.", 'cs'),
    Line('ba3', CloverMood.determined, "Stacking for bills: {amount}. That's grown-up money moves.", 'cs'),
    Line('ba4', CloverMood.happy, "Nice! {amount} set aside so bills don't hurt later.", 'f'),
    Line('ba5', CloverMood.smug, "{amount} in the bill envelope. Bills can kiss my ass now.", 's', true),
  ],
  'bill_envelope_use': [
    Line('bu1', CloverMood.proud, "Used {amount} from the bill envelope. That's exactly what it's for!"),
    Line('bu2', CloverMood.smug, "Bill paid from the envelope. Planned it, paid it. Zero panic.", 'cs'),
    Line('bu3', CloverMood.happy, "That's the envelope doing its job. {amount}, handled. Proud of you.", 'f'),
    Line('bu4', CloverMood.determined, "Envelope money hitting a bill? That's the whole plan working.", 's'),
    Line('bu5', CloverMood.proud, "{amount} from the envelope, bill handled. Hell yes, the plan WORKS.", 'cs', true),
  ],
  'goal_complete': [
    Line('gc1', CloverMood.celebrating, "WE'RE RICH! Okay, not rich. BUT WE'RE GOING SOMEWHERE! {goal} is DONE!", 'cs'),
    Line('gc2', CloverMood.celebrating, "{goal} complete! You did it. Seriously, amazing."),
    Line('gc3', CloverMood.excited, "GOAL SMASHED! {goal}! I'M DOING A LITTLE DANCE!", 'c'),
    Line('gc4', CloverMood.smug, "{goal}: finished. Didn't think you had it in you. Kidding. Mostly.", 's'),
    Line('gc5', CloverMood.celebrating, "{goal} IS FUCKING DONE! HA HA HA! I'M SCREAMING!", 'cs', true),
  ],
  'bill_paid': [
    Line('bp1', CloverMood.proud, "{bill} paid! One less thing to worry about."),
    Line('bp2', CloverMood.smug, "{bill}: handled. Look at you being a functional adult.", 'cs'),
    Line('bp3', CloverMood.happy, "{bill} is paid. Nice and on time!", 'f'),
    Line('bp4', CloverMood.smug, "{bill}, {amount}, paid. Damn right.", 's', true),
    Line('bp5', CloverMood.determined, "{bill} paid. Next.", 's'),
  ],
  'debt_cleared': [
    Line('dc1', CloverMood.celebrating, "{bill} is PAID OFF! Debt-free on that one!"),
    Line('dc2', CloverMood.celebrating, "{bill} IS DEAD! WE KILLED IT! (the debt. just the debt.)", 'c'),
    Line('dc3', CloverMood.celebrating, "{bill} is gone. Paid off. HELL YES. Free at last!", 'cs', true),
  ],
  'transfer': [
    Line('tr1', CloverMood.thinking, "Moved {amount}. Same money, new pocket."),
    Line('tr2', CloverMood.bored, "{amount} shuffled around. Not income, not spending. Just vibes.", 'cs'),
  ],
  'night': [
    Line('ng1', CloverMood.sleepy, "It's late. Close the shopping apps. Goodnight, money man.", 'cs'),
    Line('ng2', CloverMood.sleepy, "Late-night check-in? You're doing great. Get some sleep.", 'f'),
    Line('ng3', CloverMood.sleepy, "Zzz... no impulse buys after midnight... zzz", 's'),
    Line('ng4', CloverMood.sleepy, "*whispers* it's late... the carts are calling... don't listen to them...", 'c'),
  ],
  // ---- weekly recap
  'recap_great': [
    Line('rg1', CloverMood.proud, "Great week! You earned {income}, spent {spent}, and saved {saved}."),
    Line('rg2', CloverMood.excited, "WHAT A WEEK! {saved} SAVED! I'M TELLING EVERY RACCOON I KNOW!", 'c'),
    Line('rg3', CloverMood.smug, "{saved} saved this week. Okay, I'll admit it. Impressive.", 's'),
    Line('rg4', CloverMood.proud, "{saved} saved and spending's down. Damn, that's a good week.", 'cs', true),
  ],
  'recap_improving': [
    Line('ri1', CloverMood.proud, "{weeks} weeks in a row of spending less. That's a real habit forming."),
    Line('ri2', CloverMood.determined, "{weeks} WEEKS STRAIGHT OF IMPROVEMENT! THE STREAK LIVES!", 'c'),
    Line('ri3', CloverMood.smug, "{weeks} weeks better than the last. Who the hell are you now?", 's', true),
    Line('ri4', CloverMood.smug, "{weeks} weeks of spending less. Fine. You're good at this.", 's'),
  ],
  'recap_overspent': [
    Line('ro1', CloverMood.shocked, "This week: {spent} spent, up {change} from last week. Let's aim lower next week."),
    Line('ro2', CloverMood.shocked, "{spent} GONE. {change} more than last week. WHERE DID IT GO?! (I know. It's in the list.)", 'c'),
    Line('ro3', CloverMood.disappointed, "Spending up {change}. Next week is a fresh start.", 'f'),
    Line('ro4', CloverMood.deadInside, "{spent}. Up {change}. I'm staring into the void.", 's'),
    Line('ro5', CloverMood.angry, "{spent} spent, {change} more than last week. What the hell happened? Fresh start Monday.", 'cs', true),
  ],
  'recap_bills_risk': [
    Line('rb1', CloverMood.panicking, "Bills coming up are more than your free money. Let's plan before payday."),
    Line('rb2', CloverMood.panicking, "BILLS INCOMING AND THE WALLET IS LIGHT! Let's make a plan!", 'cs'),
  ],
  'recap_vacation_done': [
    Line('rv1', CloverMood.celebrating, "{goal} is fully funded! Vacation mode: UNLOCKED!"),
    Line('rv2', CloverMood.vacation, "{goal}: 100%! Pack your bags, I call the window seat.", 'cs'),
  ],
  'recap_quiet': [
    Line('rq1', CloverMood.bored, "Quiet week - nothing logged. If you spent money, tell me!"),
    Line('rq2', CloverMood.sleepy, "Zero activity last week. Either you're a monk or you forgot to log.", 'cs'),
  ],
  'recap_mixed': [
    Line('rm1', CloverMood.thinking, "Mixed week: {income} in, {spent} out. Steady is good."),
    Line('rm2', CloverMood.smug, "{income} in, {spent} out. Not a disaster. Not a parade either.", 's'),
    Line('rm3', CloverMood.happy, "{income} came in and you spent {spent}. Solid, steady week!", 'f'),
  ],
};

/// Fills {placeholders}. Unknown placeholders make the line unusable (returns null) so nothing is invented.
String? fillLine(String text, Map<String, String> data) {
  var ok = true;
  final out = text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final v = data[m[1]];
    if (v == null) ok = false;
    return v ?? '';
  });
  return ok ? out : null;
}
