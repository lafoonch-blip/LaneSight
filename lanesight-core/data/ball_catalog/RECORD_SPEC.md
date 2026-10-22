# Ball catalog record spec (collection format)

Used by the weekly refresh (`REFRESH.md`). One record per ball as sold (each separately sold colorway is its own record).

Output: one JSON file = a JSON array of records. UTF-8, valid JSON (no comments, no trailing commas).

## Hard rules
- **Never guess or invent a value.** If a field is not published by a source you actually fetched, set it to `null` and add the field name to `missing`.
- Every numeric spec must come from a page you fetched (manufacturer page preferred; reputable retailer like bowling.com / bowlersmart / bowlerx / bowlingball.com acceptable when the manufacturer page lacks it). List every URL you used in `spec_source_urls`.
- "Current lineup" = balls the manufacturer currently lists on its website as available (not "vault"/"discontinued"/"retired"). Include spare/plastic/urethane balls too, but mark them via `cover_type`.
- RG/differential/intermediate differential are for the **15 lb** ball. If only another weight is published, put it in `notes` and leave the 15 lb fields null.
- Do not copy marketing prose. `reaction_description` is a short paraphrase in your own words (≤ 25 words).
- Image: the manufacturer's official product photo URL (direct image file URL, e.g. .png/.jpg/.webp from the manufacturer's CDN). If you can only find it on a retailer, give that URL and set `image_source` accordingly. Do NOT download images.

## Record fields
```json
{
  "manufacturer": "Storm",                 // brand on the ball
  "parent_company": "Storm Products",      // Storm Products | Brunswick | Motiv
  "name": "Phaze II",                      // exact model name as the manufacturer writes it (no brand prefix)
  "product_line": "Signature",             // manufacturer's own line/series name if published, else null
  "performance_tier": "high",              // high | upper_mid | mid | entry | spare  (manufacturer or retailer category; say which in notes if retailer)
  "release_date": "2026-08",               // YYYY-MM or YYYY, null if unknown
  "colors": "Pacific/Teal/Black",
  "coverstock_name": "TX-16 Solid Reactive",
  "cover_type": "solid",                   // solid | pearl | hybrid | urethane | polyester | other
  "core_name": "Velocity Core",
  "core_type": "symmetric",                // symmetric | asymmetric
  "rg_15": 2.48,
  "diff_15": 0.051,
  "int_diff_15": null,                     // null for symmetric cores unless published
  "factory_finish": "1500-grit Polished",  // as published
  "recommended_oil": "medium-heavy",       // manufacturer's stated condition, verbatim-short, else null
  "mfr_ratings": {                         // ONLY what the manufacturer publishes; null if none
    "hook": null, "hook_scale": null,      // e.g. 235 on "10-250", or "High" on "Low/Med/High"
    "length": null, "length_scale": null,
    "backend": null, "backend_scale": null,
    "reaction_shape": null                 // manufacturer's shape label if any (e.g. "Arc", "Angular", "Skid/Flip")
  },
  "retailer_ratings": {                    // bowling.com product page ratings if found (same scale across brands)
    "source_url": null,
    "hook_potential": null,                // numeric if shown (scale 10-250 or whatever page states)
    "hook_potential_scale": null,
    "hook_potential_label": null,          // e.g. "High", "Medium-High"
    "length": null,                        // numeric if shown
    "length_scale": null,
    "length_label": null,                  // e.g. "Early", "Middle", "Late", "Long"
    "reaction_label": null                 // e.g. "Skid/Flip", "Strong arc"
  },
  "reaction_description": "Strong midlane read with a controllable, continuous backend.",
  "image_url": "https://.../phaze-ii.png",
  "image_source": "manufacturer",          // manufacturer | retailer
  "product_url": "https://www.stormbowling.com/...",
  "spec_source_urls": ["https://..."],
  "motion_chart": null,                   // Brunswick-family only: {"oil": 1-16, "oil_scale": "1 light - 16 heavy", "shape": 1-18,
                                         //  "shape_scale": "1 smooth - 18 angular", "source": "Brunswick Ball Motion Comparison Chart",
                                         //  "source_url": "<pdf>"} read off the current poster; null if the ball isn't on it
  "status": "current",                    // set by refresh merge; never by hand
  "missing": ["int_diff_15"],
  "notes": null
}
```

## Process (initial build; the weekly refresh in REFRESH.md only collects NEW balls in full)
1. Find the manufacturer's current ball listing page and enumerate every current ball.
2. For each ball fetch its product page (and bowling.com page for retailer ratings when the manufacturer gives no hook/length rating — try at least the bowling.com page for every non-spare ball).
3. Write the array to the output path as you go (rewrite the file every ~10 balls so progress isn't lost).
4. Finish with a short report: count of balls, how many have each of rg/diff/image/mfr_ratings/retailer_ratings, and any balls you could not complete.
