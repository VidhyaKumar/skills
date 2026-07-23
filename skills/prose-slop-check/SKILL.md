---
name: prose-slop-check
description: >
  Detect and remove the statistical fingerprints of AI writing (negative
  parallelism / "not X but Y", em-dash abuse, rule-of-three, false ranges,
  puffery vocabulary, uniform cadence, hedged both-sidesing) while preserving
  the writer's personal voice. Two modes: detect-only audit, or a full
  scan-rewrite-rescan loop targeting the text's genre — academic article,
  tweet, reddit post, email, blog, anything between. Use when the user says
  "slop check", "deslop this", "remove the AI tells", "humanize this", "make
  this not sound like AI", asks whether writing reads as AI, or invokes
  /prose-slop-check. Also use before publishing any agent-drafted prose.
---

# Prose Slop Check

Strip every mark of AI writing from a text and make it good in its genre, without erasing the author. Not "make it pass a detector" — make it read like a specific person with a specific point wrote it for a specific audience.

## Two jobs

**Edit (default).** The user shares a draft to fix. Run the full loop below and return the rewritten text plus a change log.

**Detect.** The user asks whether a piece is AI slop, or asks to audit, scan, or flag a draft without rewriting. Run Phase 1 only: name each pattern found, quote the line, give the fix in a few words. Do not rewrite, score the draft, or guess whether AI wrote it — AI detectors guess; named patterns are evidence the user can check. Offer to edit after.

## Why this is a loop, not a style guide

The worst tells — above all the **"not X but Y"** family — are not vocabulary mistakes. They are emergent properties of how LLMs generate text: preference tuning rewards balanced, contrastive, comprehensive-sounding framing, so the contrast move is baked into the model's priors. Two consequences drive this skill's architecture:

1. **You cannot reliably see your own slop.** The same priors that produce the pattern make it invisible on re-read. Detection must be mechanical — regex against a fixed catalog — never "does this look AI to me?"
2. **Rewriting reintroduces slop.** Ask a model to remove "it's not just X, it's Y" and it produces "this is less about X than Y" — the same move in a wig. So every rewrite gets re-scanned, and the loop runs until the scan is clean.

Workflow: **Fix target → Scan → Diagnose → Rewrite by meaning → Re-scan → (repeat) → Register check → Eval.**

## Phase 0: Fix the target

Before touching the text, establish:

- **Genre and venue** — academic article, tweet, reddit post, LinkedIn, email, blog, docs, marketing. If not stated and not obvious from the text, ask. Genre decides which tells are fatal and what "good" means; see [references/voices.md](references/voices.md).
- **Audience and stance** — who reads it, and what the author actually claims. Slop is what fills the space where a claim should be; you cannot remove it without knowing the claim.
- **Constraints** — length limits, required citations, house style.
- **Voice signals** — if the draft is human-written (or human-edited), identify 3-5 traits to preserve: vocabulary, cadence, bluntness, humor, uncertainty, digressions, level of polish. Keep this note internal. These traits are protected through every rewrite pass; the goal is that the writer still recognizes the text as their own.

## Phase 1: Mechanical scan

Run the detection patterns from [references/tells.md](references/tells.md) against the text. If the text is in a file (or you can write it to a temp file), run the grep commands in that reference literally — the catalog is written as runnable `grep -Ein` patterns. Otherwise apply each pattern by hand, line by line.

Produce a finding list: line/sentence, matched pattern, tell category. Also run the two structural checks that regex can't fully catch:

- **Cadence**: flag any run of 3+ consecutive sentences within ±4 words of the same length, and any paragraph where every sentence has the same shape (subject–verb–elaboration).
- **Formatting**: bold scattered through prose, emoji-decorated headers or bullets, "**Term:** definition" bullet lists, headers on a text too short to need them, a tidy intro–three-points–conclusion skeleton.

Report the findings to the user as a short table before rewriting (category, count, worst example). This is the diagnosis; the user should see what was wrong. For a detect request, stop here.

## Phase 2: Rewrite by meaning, not by frame

Go finding by finding, making the **minimum effective edit**. Two cardinal rules:

- **Never fix a pattern by paraphrasing the pattern.** Fix it by deciding what the sentence actually asserts, then asserting that.
- **Leave strong human sentences alone.** Fix findings, errors, and genuinely tangled passages; do not make every paragraph equally tidy, rewrite distinctive lines for consistency, or compress rough-but-real writing into generic polish. Cutting should be proportional to the actual slop.

### The "not X but Y" family — three-way triage

Every negative parallelism gets exactly one of these treatments:

1. **The negation is a strawman** (nobody believes X). Delete the X half entirely and assert Y directly, with whatever evidence the text has.
   - *"It's not just a tool, it's a fundamental shift in how teams work"* → *"Teams that adopted it stopped holding standups within a month."*
2. **The contrast is real** (people genuinely hold X). Then earn it: name who holds X, say concretely why Y beats it. A real contrast survives being made specific; slop doesn't.
3. **The sentence asserts nothing** (the contrast is decoration on an empty claim). Delete the whole sentence. Most cases are this one.

Banned escape hatches — these are the same move and count as new findings: "less about X than Y", "X matters, but Y matters more", "the real X is Y", "the question isn't X, it's Y", "X? Y." (rhetorical-question variant), and the em-dash variant "— not X, but Y".

### Everything else

- **Puffery and inflated vocabulary** (pivotal, seismic, testament, tapestry, landscape, delve…): replace with the plain word, or with the concrete fact the puffery was hiding. "Plays a vital role in" → "does".
- **Rule-of-three lists**: keep the strongest item, cut the rest — unless all three carry distinct information, in which case keep them and break the rhythm (different lengths, different syntax).
- **False ranges** ("from X to Y"): if you can't name a meaningful midpoint between X and Y, it's not a range — name the two things or cut one.
- **Hedged both-sidesing** ("it's worth noting", auto-counterpoints, "while X, it's also true that Y"): commit. One opinion, stated, owned. A counterpoint stays only if the author genuinely concedes it. But keep "I think", "maybe", "to be honest" when they express the author's real uncertainty or spoken rhythm — reflexive balance is the tell, not honest doubt.
- **Uniform cadence**: vary deliberately. Follow a long sentence with a short one. Fragments are legal. Don't apply a formula (alternating long/short is its own tell) — read the paragraph aloud and break wherever the rhythm is metronomic. Keep the author's longer spoken sentences and pace changes when they are clear and characteristic.
- **Low specificity**: replace "many companies" / "studies show" / "recent research" with the actual names, numbers, and dates — **only from the source text, the conversation, or verifiable research you actually do**. Never invent specifics. If the author needs to supply one, leave a marked placeholder: `[ADD: which study?]`. Protect existing specifics the other way too: never smooth a concrete detail into generic importance.
- **Stock skeleton**: kill throat-clearing openers ("In today's fast-paced world…"), summary conclusions ("In conclusion… Ultimately…"), engagement-bait endings ("What do you think?"), and fake-profound kickers — delete the final "deep" metaphor or mic-drop line rather than rewriting it into a better one, and end on the clearest concrete sentence already in the draft. Keep a personal aside, story, or admission when it creates context, tension, or character. Preserve the author's structure and detours unless they hurt the piece; if you reorganize, say why in the change log.

### What not to do — overcorrection is also slop

- No fake typos, forced slang, or manufactured "voice". Humanizer-tool output is its own genre of slop.
- Em dashes are not banned. Humans use them. The tell is density and the double-dash "— not X, but —" move. Budget: at most one em dash per ~150 words, never two in a sentence.
- Don't trade precision for personality in academic or technical text. There, de-slopping means cutting puffery and committing to claims — not adding attitude.
- Don't sand off the author's edge. Strong opinions, blunt language, humor, profanity, self-interruptions, and honest admissions stay when they belong to the writer; never replace them with safer or more professional wording.
- Preserve the author's meaning, claims, and facts exactly. This is a style pass, not a content edit. Flag, don't silently fix, anything that looks factually wrong.

## Phase 3: Verify loop

Re-run the full Phase 1 scan **on your rewritten text**. This step is not optional and not a formality — expect your own rewrite to contain new tells, because the model writing it has the same priors that created them. Fix and re-scan until a pass produces zero pattern hits and the cadence check passes. Cap at 4 passes; if a pattern survives 4 passes, rewrite that sentence from scratch starting from its bare claim ("what fact or opinion is this sentence for?").

## Phase 4: Register and voice check

Check the clean text against its genre profile in [references/voices.md](references/voices.md): right length, right formality, right person, genre-specific tells gone (e.g. on reddit: no bold, no bullet essay; in academic prose: no first-person hot takes added).

Then run the checklist in [eval.md](eval.md). Every check must pass; fix and re-check on failure. The two that matter most: would the writer recognize this as their own voice, and would it sound natural read aloud to a sharp colleague? Anywhere you wouldn't say it to the actual audience, rewrite that sentence.

Deliver: the rewritten text, plus a brief change log (categories fixed, counts, number of verify passes, and any structural reorganization with its reason).
