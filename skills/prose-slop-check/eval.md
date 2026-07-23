# Prose Slop Check eval

Use this in Phase 4, after the verify loop is clean. Answer each check with pass or fail. If any check fails, fix the draft and re-run the Phase 1 scan before returning it.

For detect requests, skip this file; instead make sure the response names each pattern found with a quoted line and a short fix, without rewriting, scoring, or claiming AI authorship.

## Meaning and voice

1. Does the edit preserve the author's point, claims, and facts without adding claims, examples, stats, quotes, or opinions?
2. Does it preserve the voice signals noted in Phase 0: vocabulary, cadence, bluntness, humor, uncertainty, digressions, level of polish?
3. Are strong human sentences left alone instead of rewritten for consistency or tidiness?
4. Is the amount of cutting proportional to the actual slop, with no compression that strips out character?
5. Are strong opinions, blunt language, profanity, and honest admissions kept rather than replaced with safer wording?
6. Are useful concrete details protected, not smoothed into generic importance?
7. Are all specifics real — from the source text, the conversation, or actual research — with placeholders like `[ADD: which study?]` where the author must supply one?

## Patterns

1. Zero pattern hits from references/tells.md on the final text, including the banned escape-hatch paraphrases of "not X but Y"?
2. Are rule-of-three lists, false ranges, and reflexive both-sidesing resolved by triage, not paraphrase?
3. Are throat-clearing openers, summary-recap endings, engagement bait, and fake-profound kickers deleted (not rewritten into better versions), with the text ending on a concrete point, takeaway, or next action?
4. Is weasel attribution replaced with named sources or flagged to the user when no source exists?
5. Is formatting slop gone: emoji headers, decorative bold, "Term: definition" bullets outside docs, headers on tiny sections?
6. Em dashes within budget: at most ~1 per 150 words, never two in a sentence, no "— not X, but Y"?

## Cadence and register

1. Does sentence length and shape vary — no runs of 3+ same-length sentences, no uniform paragraph sizes, no stacked punchy fragments?
2. Does the text match its genre profile in references/voices.md: length, formality, person, genre-specific tells gone?
3. No overcorrection: no fake typos, forced slang, or manufactured personality; precision intact in academic or technical text?

## Final read

1. Would the writer recognize the edited draft as their own voice?
2. Would it sound natural read aloud to the actual audience?
3. Does the final output include the full rewritten text and a brief change log (categories fixed, counts, verify passes, any reorganization with its reason)?
