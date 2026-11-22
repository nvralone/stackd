// Categorized, rules-based dialogue library. Placeholders are filled ONLY from real recorded data.
// p: personalities allowed ('f' friendly, 'c' chaotic, 's' savage); empty = all.
import 'moods.dart';

class Line {
  final String id, text, p;
  final CloverMood mood;
  const Line(this.id, this.mood, this.text, [this.p = '']);
  bool fits(String personality) => p.isEmpty || p.contains(personality[0]);
}

const Map<String, List<Line>> dialogue = {
  'no_data': [
    Line('nd1', CloverMood.thinking, "Hi! I'm Clover. Log some money and I'll start judging. Lovingly."),
    Line('nd2', CloverMood.confused, "Empty ledger? Bold strategy. Tap Quick Add and let's get stacking.", 'cs'),
    Line('nd3', CloverMood.happy, "Let's set up your first account. I promise I'm mostly helpful.", 'f'),
    Line('nd4', CloverMood.suspicious, "No transactions yet. Either you're perfect or you're hiding receipts. I don't do receipts, so... tell me.", 'cs'),
  ],
  'idle': [
    Line('id1', CloverMood.happy, "You've got {available} free until {payday}. That's {daily} a day. Spend it like you mean it."),
    Line('id2', CloverMood.smug, "{available} safe to spend. I did the math. You're welcome.", 'cs'),
    Line('id3', CloverMood.happy, "Looking good! About {daily} a day keeps you on track until {payday}.", 'f'),
    Line('id4', CloverMood.bored, "Nothing's on fire. Honestly kinda boring. {daily} a day, money man.", 'cs'),
    Line('id5', CloverMood.thinking, "Daily safe spend: {daily}. Stay under it and I stay quiet. Mostly.", 'cs'),
    Line('id6', CloverMood.smug, "{daily} a day. Not a fortune, but it's YOUR fortune.", 's'),
    Line('id7', CloverMood.happy, "Steady week so far. Proud of you for checking in.", 'f'),
  ],
  'tight': [
    Line('ti1', CloverMood.thinking, "Things are tight: {daily} a day until {payday}. We can do this."),
    Line('ti2', CloverMood.determined, "Lean mode activated. {daily} a day. Ramen arc begins NOW.", 'cs'),
    Line('ti3', CloverMood.deadInside, "{daily} per day. I've seen bigger numbers on a vending machine.", 's'),
  ],
  'bills_at_risk': [
    Line('br1', CloverMood.panicking, "UH OH. Bills before payday are {reserved} and free money is short by {short}. Let's look at this together."),
    Line('br2', CloverMood.panicking, "RED ALERT! You're {short} short for bills coming up. Pause the fun stuff, okay?", 'cs'),
    Line('br3', CloverMood.thinking, "Heads up: upcoming bills need {short} more than you have free. Want to move some money around?", 'f'),
    Line('br4', CloverMood.shocked, "The bills want {reserved}. The wallet says no. We're {short} short, chief.", 's'),
  ],
  'bill_due': [
    Line('bd1', CloverMood.suspicious, "HEY, MONEY MAN. {bill} ({amount}) is due {when}. DON'T ACT SURPRISED.", 'cs'),
    Line('bd2', CloverMood.thinking, "Friendly reminder: {bill} for {amount} is due {when}.", 'f'),
    Line('bd3', CloverMood.suspicious, "{bill}. {amount}. {when}. I'm watching.", 's'),
    Line('bd4', CloverMood.determined, "{bill} is coming {when}. {amount}. We've got this.", 'f'),
    Line('bd5', CloverMood.smug, "{bill} drops {when}. {amount}. Pay it and I'll stop tapping my foot.", 'cs'),
  ],
  'bill_overdue': [
    Line('bo1', CloverMood.angry, "{bill} was due {when}. {amount} still open. Let's handle it today!"),
    Line('bo2', CloverMood.panicking, "OVERDUE! {bill}! {amount}! THE CLOCK IS LOUD!", 'cs'),
    Line('bo3', CloverMood.thinking, "{bill} slipped past its due date. If you already paid, mark it so I calm down.", 'f'),
    Line('bo4', CloverMood.deadInside, "{bill}. Overdue. {amount}. I'm not mad. I'm just... yeah, I'm mad.", 's'),
  ],
  'fast_food': [
    Line('ff1', CloverMood.shocked, "BROTHER. THE DRIVE-THRU WORKERS KNOW YOUR NAME AT THIS POINT. {visits} visits, {amount} this week.", 'cs'),
    Line('ff2', CloverMood.thinking, "Fast food is at {amount} this week ({visits} trips). Maybe a grocery run next?", 'f'),
    Line('ff3', CloverMood.deadInside, "{visits} fast food runs. {amount}. The fries are winning.", 's'),
    Line('ff4', CloverMood.suspicious, "Another drive-thru? That's {visits} this week. I can smell the nuggets from here.", 'cs'),
    Line('ff5', CloverMood.disappointed, "{amount} on fast food. You could've had a whole grocery cart.", 's'),
  ],
  'overspent': [
    Line('os1', CloverMood.disappointed, "{category} is over budget by {amount}. It happens - let's reel it in."),
    Line('os2', CloverMood.shocked, "{category} WENT {amount} OVER. WHO AUTHORIZED THIS?!", 'cs'),
    Line('os3', CloverMood.thinking, "{category} is {amount} past its limit. Want to cover it with extra money?", 'f'),
    Line('os4', CloverMood.angry, "{category}: {amount} over. The budget was a suggestion apparently.", 's'),
    Line('os5', CloverMood.smug, "{category} blew its limit by {amount}. I'm adding this to your permanent record.", 'cs'),
  ],
  'saved_week': [
    Line('sw1', CloverMood.proud, "WAIT. YOU ACTUALLY STUCK TO THE BUDGET?! I'M SO PROUD OF YOU!", 'cs'),
    Line('sw2', CloverMood.proud, "You're spending {amount} less than last week. That's real progress!", 'f'),
    Line('sw3', CloverMood.smug, "{amount} less than last week. Who are you and what did you do with my spender?", 's'),
    Line('sw4', CloverMood.excited, "DOWN {amount} FROM LAST WEEK! LOOK AT YOU GO!", 'c'),
  ],
  'vacation_near': [
    Line('vn1', CloverMood.vacation, "{trip} in {days} days! You're {pct}% funded. I'm packing my tiny sunglasses."),
    Line('vn2', CloverMood.vacation, "{days} DAYS UNTIL {trip}! {pct}% SAVED! BEACH RACCOON MODE LOADING...", 'c'),
    Line('vn3', CloverMood.thinking, "{trip} is {days} days out and {pct}% funded. Keep feeding that vault.", 's'),
  ],
  'expense': [
    Line('ex1', CloverMood.thinking, "Logged {amount} in {category}. Noted."),
    Line('ex2', CloverMood.suspicious, "{amount} on {category}. I saw that.", 'cs'),
    Line('ex3', CloverMood.happy, "Got it! {amount} for {category}. Thanks for keeping me posted.", 'f'),
    Line('ex4', CloverMood.bored, "{category}, {amount}. Riveting.", 's'),
    Line('ex5', CloverMood.smug, "Into the ledger it goes. {amount}. {category}. Forever.", 'c'),
  ],
  'essential': [
    Line('es1', CloverMood.determined, "{amount} for {category}. Necessary stuff. No judgment here."),
    Line('es2', CloverMood.happy, "Adulting! {amount} on {category}. Responsible raccoon approves.", 'cs'),
  ],
  'big_expense': [
    Line('be1', CloverMood.shocked, "Whoa, {amount}! That's a big chunk of your spending money. Everything okay?"),
    Line('be2', CloverMood.shocked, "{amount}?!?! MY TAIL JUST FELL OFF.", 'c'),
    Line('be3', CloverMood.deadInside, "{amount}. Okay. Cool. Cool cool cool.", 's'),
  ],
  'income': [
    Line('in1', CloverMood.dollarEyes, "PAYDAY! {amount} landed! Let's give every dollar a job."),
    Line('in2', CloverMood.dollarEyes, "MONEY! {amount}! I can hear it crinkling!", 'c'),
    Line('in3', CloverMood.happy, "{amount} came in. Nice work! Want to split it?", 'f'),
    Line('in4', CloverMood.smug, "{amount} income. Try to keep it longer than a weekend this time.", 's'),
  ],
  'extra_money': [
    Line('xm1', CloverMood.excited, "BONUS CASH! {amount} from {source}! Let's be smart with it!"),
    Line('xm2', CloverMood.dollarEyes, "{amount} FROM {source}?! FREE MONEY ENERGY!", 'c'),
    Line('xm3', CloverMood.happy, "Extra {amount} from {source}. Even a little to savings helps!", 'f'),
    Line('xm4', CloverMood.smug, "{amount} from {source}. Don't spend it on nuggets.", 's'),
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
  ],
  'vacation_withdraw': [
    Line('vw1', CloverMood.begging, "YOU'RE ROBBING YOUR FUTURE SELF! DON'T YOU WANNA BE ON A BEACH RIGHT NOW?!", 'cs'),
    Line('vw2', CloverMood.disappointed, "Taking {amount} from {goal}? Okay... the beach will wait a little longer.", 'f'),
    Line('vw3', CloverMood.crying, "{amount} out of {goal}. The sand. The waves. Gone.", 's'),
    Line('vw4', CloverMood.begging, "Nooo, not the trip fund! {amount}?! Think of the tiny umbrellas!", 'c'),
  ],
  'goal_withdraw': [
    Line('gw1', CloverMood.disappointed, "Pulled {amount} from {goal}. We'll build it back."),
    Line('gw2', CloverMood.suspicious, "{amount} out of {goal}... for what, exactly?", 'cs'),
    Line('gw3', CloverMood.deadInside, "{goal} just lost {amount}. I need a minute.", 's'),
  ],
  'emergency_withdraw': [
    Line('ew1', CloverMood.determined, "Emergency covered with {amount} from {goal}. That's exactly what savings are for."),
    Line('ew2', CloverMood.thinking, "Using {amount} for an emergency? Good call. No guilt. We rebuild later.", 'f'),
    Line('ew3', CloverMood.determined, "Emergency fund doing its job. {amount}. I'm not even mad, that's smart.", 'cs'),
  ],
  'goal_complete': [
    Line('gc1', CloverMood.celebrating, "WE'RE RICH! Okay, not rich. BUT WE'RE GOING SOMEWHERE! {goal} is DONE!", 'cs'),
    Line('gc2', CloverMood.celebrating, "{goal} complete! You did it. Seriously, amazing."),
    Line('gc3', CloverMood.excited, "GOAL SMASHED! {goal}! I'M DOING A LITTLE DANCE!", 'c'),
    Line('gc4', CloverMood.smug, "{goal}: finished. Didn't think you had it in you. Kidding. Mostly.", 's'),
  ],
  'bill_paid': [
    Line('bp1', CloverMood.proud, "{bill} paid! One less thing to worry about."),
    Line('bp2', CloverMood.smug, "{bill}: handled. Look at you being a functional adult.", 'cs'),
  ],
  'debt_cleared': [
    Line('dc1', CloverMood.celebrating, "{bill} is PAID OFF! Debt-free on that one!"),
    Line('dc2', CloverMood.celebrating, "{bill} IS DEAD! WE KILLED IT! (the debt. just the debt.)", 'c'),
  ],
  'transfer': [
    Line('tr1', CloverMood.thinking, "Moved {amount}. Same money, new pocket."),
    Line('tr2', CloverMood.bored, "{amount} shuffled around. Not income, not spending. Just vibes.", 'cs'),
  ],
  'night': [
    Line('ng1', CloverMood.sleepy, "It's late. Close the shopping apps. Goodnight, money man.", 'cs'),
    Line('ng2', CloverMood.sleepy, "Late-night check-in? You're doing great. Get some sleep.", 'f'),
    Line('ng3', CloverMood.sleepy, "Zzz... no impulse buys after midnight... zzz", 's'),
  ],
  // ---- weekly recap
  'recap_great': [
    Line('rg1', CloverMood.proud, "Great week! You earned {income}, spent {spent}, and saved {saved}."),
    Line('rg2', CloverMood.excited, "WHAT A WEEK! {saved} SAVED! I'M TELLING EVERY RACCOON I KNOW!", 'c'),
    Line('rg3', CloverMood.smug, "{saved} saved this week. Okay, I'll admit it. Impressive.", 's'),
  ],
  'recap_improving': [
    Line('ri1', CloverMood.proud, "{weeks} weeks in a row of spending less. That's a real habit forming."),
    Line('ri2', CloverMood.determined, "{weeks} WEEKS STRAIGHT OF IMPROVEMENT! THE STREAK LIVES!", 'c'),
  ],
  'recap_overspent': [
    Line('ro1', CloverMood.shocked, "This week: {spent} spent, up {change} from last week. Let's aim lower next week."),
    Line('ro2', CloverMood.shocked, "{spent} GONE. {change} more than last week. WHERE DID IT GO?! (I know. It's in the list.)", 'c'),
    Line('ro3', CloverMood.disappointed, "Spending up {change}. Next week is a fresh start.", 'f'),
    Line('ro4', CloverMood.deadInside, "{spent}. Up {change}. I'm staring into the void.", 's'),
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
