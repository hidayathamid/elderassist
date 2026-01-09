# emergencies_disability_assistance_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Recommendation Rules (Booking Caregiver)
`BookingCaregiverScreen` reads recommendation thresholds/weights from Firestore so tiering logic is configurable (not hardcoded in UI).

- Collection: `recommendationRules`
- Document: `current`
- Fields (numbers):
  - `maxRuleDistanceKm` (default `12.0`)
  - `preferredDistanceKm` (default `6.0`)
  - `minAcceptableRating` (default `3.0`)
  - `ratingPenaltyThreshold` (default `3.5`)
  - `ratingPenaltyValue` (default `-10.0`)
  - `recommendationTier1MinScore` (Class 1 threshold, default `2600.0`)
  - `recommendationTier2MinScore` (Class 2 threshold, default `2200.0`)
  - `distanceScoreMultiplier` (default `8.0`)
  - `ratingScoreMultiplier` (default `15.0`)
  - `matchScoreMultiplier` (default `1200.0`)
  - `serviceScoreMultiplier` (default `3.0`)
  - `serviceScoreCap` (integer, default `6`)
  - `priceScoreMultiplier` (default `-6.0`)
  - `distancePenaltyMultiplier` (default `-2.0`)

If the document is missing, the app falls back to the defaults above.
