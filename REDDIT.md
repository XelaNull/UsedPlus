# Reddit Beta Testing Recruitment Post

**Subreddit:** r/farmingsimulator
**Flair:** [Mod] or [FS25]

---

## Post Title Options

Choose one:
- `[FS25] UsedPlus: 29,000 lines of code, zero written by me - AI-built financial overhaul (Beta Testers Wanted)`
- `[FS25 Mod] UsedPlus - Used equipment marketplace, financing, partial repaints (skip that $40k bill), and more (Beta Testers Needed)`
- `[FS25] I used AI to build a massive finance mod - looking for testers before release`

---

## Post Body

---

# UsedPlus: A Complete Financial Overhaul for FS25

**29,000 lines of code. 52 Lua files. 30 custom dialogs. And I didn't write a single line.**

I'm going to tell you about UsedPlus - a mod that transforms FS25's economy from "can I afford this yes/no" into something that actually feels like running a farm business. But first, I want to be upfront about something unusual: **this entire mod was written by AI.**

I used Claude Code (Anthropic's coding AI) for every function, every dialog, every calculation. My role was vision, testing, and feedback - but the actual implementation? That was Claude and "Samantha" (an AI persona focused on catching edge cases and UX issues). More on that later, because I think it says something interesting about where modding is headed.

But first - what does UsedPlus actually do?

---

## The Problem With Vanilla FS25

You see a $450,000 combine in the shop. In vanilla, you have exactly two options:
1. Buy it (if you have the cash)
2. Don't buy it

That's it. No financing. No hunting for a used one at 40% off. No building credit history. No leasing land instead of buying it outright. No deciding whether to fully repair a beater or just patch it enough for one more harvest.

**Real farmers don't operate this way.** They finance equipment over decades. They hunt for deals at auctions. They nurse aging machinery through "just one more season." They build relationships with lenders. They make calculated gambles on used equipment that might be a reliable workhorse... or a money pit.

UsedPlus brings all of that to FS25.

---

## The Used Equipment Marketplace

In vanilla, you wait and hope the vehicle you want randomly shows up in the dealer's used section. Maybe it does. Maybe it doesn't. Maybe it's the wrong configuration.

**UsedPlus flips this.** You hire an agent to hunt for *exactly* the vehicle you want.

### How Buying Works

1. **Open the Shop** → Find the vehicle you want → Click "Search Used"
2. **Choose Your Agent:**
   - **Local Agent** (2% fee): Searches nearby. Faster results (1-7 days), but smaller selection. Higher chance of finding rough equipment.
   - **Regional Agent** (4% fee): Wider search. 1-3 weeks, better selection, more balanced quality.
   - **National Agent** (6% fee): Searches everywhere. 2-6 weeks, but finds the cream of the crop.

3. **Choose Your Quality Tier:**
   - **Poor Condition** (60-80% off): Cheap, but expect problems. Maybe a hidden gem. Maybe a disaster.
   - **Fair/Good** (30-50% off): Balanced risk/reward
   - **Excellent** (10-20% off): Nearly new, minimal risk

4. **Wait for Results** → Agent finds vehicles over time
5. **Inspect Before Buying** → Pay for a mechanic's inspection to reveal hidden issues

### The Gamble: Workhorses vs. Lemons

Here's where it gets interesting. Every used vehicle has **hidden "DNA"** that you can't see directly - it determines whether you found a diamond in the rough or bought someone else's problem.

- **Workhorses**: These machines just keep running. Repair them 50 times and they're still going strong. The previous owner sold it because they upgraded, not because it was failing. You got lucky.

- **Lemons**: Money pits. Every repair makes them slightly worse long-term. The reliability ceiling *drops* with each fix. After years of repairs, you realize you can't get it running right no matter how much you spend. The previous owner knew exactly what they were doing when they sold it.

**The mechanic gives you hints.** When you pay for an inspection, the mechanic drops a quote:

> *"In 30 years, I've seen maybe a dozen this well built."*
>
> **Translation: BUY THIS IMMEDIATELY**

> *"She's about as reliable as a screen door on a submarine."*
>
> **Translation: RUN**

50 unique quotes across 10 quality tiers. Pay attention to the mechanic's tone - it could save you $50,000 in future repairs.

---

## Selling: Your Own Agent Network

Vanilla instant-sell gives you pennies on the dollar. UsedPlus replaces it entirely.

### How Selling Works

1. **List Your Vehicle** → Choose agent tier and pricing strategy
2. **Agent Markets It** → They find buyers over time
3. **Receive Offers** → A popup appears: "BUYER FOUND! Offer: $52,500"
4. **Accept or Decline** → Good deal? Take it. Want more? Keep waiting.

### Pricing Strategies

| Strategy | Price Range | Success Rate | Best For |
|----------|-------------|--------------|----------|
| **Fire Sale** | 75-85% of value | High | Need cash NOW |
| **Fair Market** | 95-105% of value | Medium | Balanced approach |
| **Premium** | 115-130% of value | Lower | Pristine equipment, patient seller |

The better your agent (National > Regional > Local), the better offers you'll receive - but they take longer and charge more.

---

## Financing: Stop Draining Your Bank Account

That $450,000 combine? Now you can:

- **Finance it** over 1-30 years
- **Choose your down payment** (0-50%)
- **See real amortization** - monthly payments calculated properly
- **Build credit history** - on-time payments improve your score
- **Pay extra when flush** - accelerate payoff with no penalty

### Credit Scores (300-850)

Your financial behavior matters:

| Score Range | Rating | Interest Impact |
|-------------|--------|-----------------|
| 750+ | Excellent | -1.5% rate |
| 700-749 | Good | -0.5% rate |
| 650-699 | Fair | +0.5% rate |
| 600-649 | Poor | +1.5% rate |
| <600 | Very Poor | +3.0% rate |

Miss payments? Score drops. Pay on time? Score rises. Pay off loans early? Big bonus.

---

## Farmland Leasing & Financing

**This doesn't exist in vanilla at all.**

Can't afford to buy that field outright? Now you can:

- **Lease farmland** for 1, 3, 5, or 10 years
- **Lower annual costs** with longer terms
- **Buyout option** - convert your lease to ownership mid-term
- **Finance purchases** - spread land costs over years

But be careful: **3 missed payments = land seizure.** Your credit takes a massive hit and you lose the field.

---

## Farmland Difficulty Scaling

**Ever notice that vanilla scales vehicle prices by difficulty, but not land?** On Easy mode you get 40% cheaper tractors, but fields cost the same as Hard mode. That's inconsistent.

UsedPlus fixes this. When enabled, farmland prices follow the same difficulty multipliers as everything else:

| Difficulty | Price Multiplier |
|------------|------------------|
| **Easy** | 60% of base price |
| **Normal** | 100% (unchanged) |
| **Hard** | 140% of base price |

Toggle it on or off in settings - some players prefer static land prices, and that's fine.

---

## Earn Interest on Your Savings

**Your money shouldn't just sit there doing nothing.**

Enable Bank Interest and your positive cash balance earns monthly interest, just like a savings account:

- **Default rate:** 1% APY
- **Configurable:** From 0% to 5% in settings
- **Calculated monthly:** $1,000,000 balance at 1% = ~$833/month
- **Scales with presets:** Easy mode gives 3.5% APY, Hardcore disables it entirely

It's a small passive income stream that rewards keeping reserves instead of spending everything immediately.

---

## Partial Repair AND Partial Repaint

**This one's going to make some of you very happy.**

You know how repainting costs a fortune? $35,000-$45,000 to repaint a combine you're probably selling in a year anyway?

Now you can:
- **Repair to 25%, 50%, 75%, or 100%**
- **Repaint to 25%, 50%, 75%, or 100%**
- **See real-time cost updates** as you adjust
- **Finance the repair** if you're short on cash

That $40,000 repaint? Do 25% for $10,000. Or skip the paint entirely and just fix the engine. Your equipment, your budget.

---

## When Things Break: The Maintenance System

Used vehicles aren't just cheaper - they're riskier.

### Three Component Systems

Every vehicle tracks:
- **Engine Health**: Affects power, fuel efficiency, stalling risk
- **Hydraulic Health**: Affects implement drift, lift reliability
- **Electrical Health**: Affects sensors, lights, random cutouts

### What Actually Happens

| Component | When It's Bad | What You Experience |
|-----------|---------------|---------------------|
| Engine | Poor | Random stalling, reduced max speed, hard starting |
| Hydraulic | Poor | Raised implements slowly drift down, steering pulls to one side |
| Electrical | Poor | Implements randomly shut off for 3 seconds |

Low-reliability vehicles aren't just abstract numbers - they actively fight you during operation.

### The Field Service Kit

Vehicle died in the middle of a field? No problem (well, some problem).

1. **Buy a Field Service Kit** from the shop ($5k-$25k depending on tier)
2. **Carry it to the disabled vehicle**
3. **Run the OBD diagnostic minigame** - choose a system, interpret readings, diagnose the cause
4. **Correct diagnosis = better repair outcome**

It's a consumable item - one use per kit. Stock up for long field sessions.

---

## Cross-Mod Integration

UsedPlus plays nice with popular mods:

### Deep Integration

| Mod | How It Works |
|-----|--------------|
| **Real Vehicle Breakdowns** | UsedPlus provides "symptoms before failure" - your engine struggles before RVB triggers catastrophic failure |
| **Use Up Your Tyres** | Tire condition syncs from UYT wear data |
| **EnhancedLoanSystem** | ELS loans display in Finance Manager, Pay Early works on ELS loans |
| **HirePurchasing** | HP leases display in Finance Manager |
| **Employment** | Worker wages included in monthly obligations |

### Compatible (Feature Deferral)

| Mod | How It Works |
|-----|--------------|
| **BuyUsedEquipment** | UsedPlus hides its Search button, lets BUE handle used search |
| **AdvancedMaintenance** | Both maintenance systems work together |

---

## The AI Story: 29,000 Lines I Didn't Write

I want to be transparent about how this mod was built, because I think it matters.

**I did not write a single line of code.**

Not one function. Not one XML element. Not one calculation. Everything was written by Claude (Anthropic's AI coding assistant) through their Claude Code tool.

### What I Did

- Provided the vision: "Make FS25 feel like running a real farm business"
- Tested constantly: Playing, breaking things, reporting bugs
- Gave feedback: "This dialog is confusing," "The math feels wrong," "Add this feature"
- Made decisions: Which features to include, how to balance them

### What AI Did

- Wrote all 52 Lua files (~24,000 lines)
- Created all 21 XML dialogs (~5,000 lines)
- Designed the architecture
- Debugged issues
- Documented everything

### By The Numbers

| Metric | Count |
|--------|-------|
| Lua files | 52 |
| XML files | 21 |
| Custom dialogs | 30 |
| Lines of Lua | ~24,000 |
| Lines of XML | ~5,000 |
| Network events | 15+ |
| Development time | ~10 days |

### Why This Matters

Could I have coded this myself? Probably. But 29,000 lines would have taken months - long enough that I would have lost interest and never finished.

AI didn't make the impossible possible. It changed the **value proposition**. A project that wasn't worth the time investment suddenly became achievable.

I think this is where modding is headed. AI as a force multiplier for people with ideas but limited time. The barrier isn't "can you code?" anymore - it's "can you articulate what you want and iterate on feedback?"

That said, **AI-generated code has blind spots.** There are probably bugs in this mod that a human programmer wouldn't have made. Your fresh eyes help catch them. That's part of why I'm looking for testers.

---

## What I'm Looking For

### Beta Testers Who Will:

1. **Actually play** - Not just install and forget
2. **Report bugs** - With steps to reproduce and log.txt if possible
3. **Give honest feedback** - "This is confusing" helps more than "looks good"
4. **Test edge cases** - What happens if you finance 50 tractors?
5. **Try multiplayer** - I especially need co-op testing

### What's Most Helpful:

- Screenshots of errors
- The `log.txt` file (in `My Games/FarmingSimulator2025/`)
- Steps to reproduce issues
- UX suggestions ("I didn't understand what this button did")

---

## Known Issues (Beta Reality)

Being honest about what's not perfect yet:

- [ ] Some dialogs may clip on ultrawide monitors
- [ ] German translation complete, other languages partial
- [ ] Performance with 100+ financed items not fully tested
- [ ] Sale offer popup redesign is new - may have edge cases

---

## How to Install

1. Download from [LINK TBD]
2. Place `FS25_UsedPlus.zip` in your mods folder:
   - Windows: `Documents\My Games\FarmingSimulator2025\mods\`
3. Enable in mod selection
4. **Keep either the .zip OR extracted folder, not both**

---

## Quick Reference

| Hotkey | Action |
|--------|--------|
| **Shift+F** | Open Finance Manager (from anywhere) |
| **U** (in shop) | Search for used equipment |

---

## Credits

Built on patterns from the FS modding community:
- EnhancedLoanSystem, BuyUsedEquipment, HirePurchasing (financial patterns)
- Real Vehicle Breakdowns, Use Up Your Tyres (maintenance integration)
- MobileServiceKit by w33zl (Field Service Kit foundation)
- Fuel models by Gian FS and WMD Modding
- **FS25_FarmlandDifficulty** by GMNGjoy (farmland scaling patterns)
- **FS25_bankAccountInterest** by Evan Kirsch (bank interest patterns)

---

## FAQ

**Q: Does this break vanilla loans?**
A: No, vanilla loans still work. UsedPlus adds on top.

**Q: Can I still instant-sell?**
A: We replace instant-sell with agent-based sales. More realistic, better returns if you wait.

**Q: Will this break my save?**
A: Shouldn't. UsedPlus data is stored separately. Disable the mod and your save continues without UsedPlus features.

**Q: Multiplayer?**
A: Fully supported.

---

**Download:** [TBD]

**GitHub Issues:** [TBD]

---

*Ready to stop playing with Monopoly money?*

---

## Pre-Post Checklist

- [ ] Take 4-6 good screenshots
- [ ] Create GitHub release with .zip
- [ ] Test download link works
- [ ] Proofread one more time
- [ ] Post on weekday afternoon (US time)
- [ ] Reply to every comment in first 24 hours

---

*Last updated: 2026-01-05*
