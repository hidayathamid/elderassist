# Seed `recommendationRules` (matrix)

This project uses:
- `recommendationRules/*` (docs other than `current`) as the matrix used by `BookingCaregiverScreen`:
  - `rating_level` (1 best → 5 worst)
  - `distance_level` (1 best → 5 worst)
  - `match_level` (1 best → 5 worst)
  - `price_gap_level` (1 best → 5 worst, based on `users.budget` vs computed `priceValue`)
  - `service_count_level` (1 best → 5 worst)
  - `recommendation_class` (1 Best match, 2 Recommended, 3 Not ideal)

`recommendationRules/current` is optional (legacy config). The app logic is matrix-driven.

## Deploy and run (one-time)
1) Set a secret:
   - `firebase functions:config:set seed.secret="YOUR_SECRET"`
2) Deploy:
   - `firebase deploy --only functions:seedRecommendationRules`
3) Seed:
   - Merge (safe): `https://<region>-<project>.cloudfunctions.net/seedRecommendationRules?secret=YOUR_SECRET&density=lite&mode=merge`
   - Replace (wipe old matrix docs): `...&mode=replace`

`density=lite` seeds a smaller but useful matrix (distance levels 1–2, other levels sampled).
Use `density=full` only if you really want a large matrix.
