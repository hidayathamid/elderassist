import 'package:cloud_firestore/cloud_firestore.dart';

class RecommendationRules {
  const RecommendationRules({
    required this.maxRuleDistanceKm,
    required this.preferredDistanceKm,
    required this.minAcceptableRating,
    required this.ratingPenaltyThreshold,
    required this.ratingPenaltyValue,
    required this.recommendationTier1MinScore,
    required this.recommendationTier2MinScore,
    required this.distanceScoreMultiplier,
    required this.ratingScoreMultiplier,
    required this.matchScoreMultiplier,
    required this.serviceScoreMultiplier,
    required this.serviceScoreCap,
    required this.priceScoreMultiplier,
    required this.distancePenaltyMultiplier,
  });

  final double maxRuleDistanceKm;
  final double preferredDistanceKm;
  final double minAcceptableRating;
  final double ratingPenaltyThreshold;
  final double ratingPenaltyValue;

  final double recommendationTier1MinScore;
  final double recommendationTier2MinScore;

  final double distanceScoreMultiplier;
  final double ratingScoreMultiplier;
  final double matchScoreMultiplier;
  final double serviceScoreMultiplier;
  final int serviceScoreCap;
  final double priceScoreMultiplier;
  final double distancePenaltyMultiplier;

  static RecommendationRules defaults() {
    return const RecommendationRules(
      maxRuleDistanceKm: 12.0,
      preferredDistanceKm: 6.0,
      minAcceptableRating: 3.0,
      ratingPenaltyThreshold: 3.5,
      ratingPenaltyValue: -10.0,
      recommendationTier1MinScore: 2600.0,
      recommendationTier2MinScore: 2200.0,
      distanceScoreMultiplier: 8.0,
      ratingScoreMultiplier: 15.0,
      matchScoreMultiplier: 1200.0,
      serviceScoreMultiplier: 3.0,
      serviceScoreCap: 6,
      priceScoreMultiplier: -6.0,
      distancePenaltyMultiplier: -2.0,
    );
  }

  static RecommendationRules fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    RecommendationRules? fallback,
  }) {
    final base = fallback ?? RecommendationRules.defaults();
    final data = doc.data();
    if (data == null) return base;

    double d(String key, double current) {
      final raw = data[key];
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim()) ?? current;
      return current;
    }

    int i(String key, int current) {
      final raw = data[key];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim()) ?? current;
      return current;
    }

    return RecommendationRules(
      maxRuleDistanceKm: d('maxRuleDistanceKm', base.maxRuleDistanceKm),
      preferredDistanceKm: d('preferredDistanceKm', base.preferredDistanceKm),
      minAcceptableRating: d('minAcceptableRating', base.minAcceptableRating),
      ratingPenaltyThreshold:
          d('ratingPenaltyThreshold', base.ratingPenaltyThreshold),
      ratingPenaltyValue: d('ratingPenaltyValue', base.ratingPenaltyValue),
      recommendationTier1MinScore:
          d('recommendationTier1MinScore', base.recommendationTier1MinScore),
      recommendationTier2MinScore:
          d('recommendationTier2MinScore', base.recommendationTier2MinScore),
      distanceScoreMultiplier:
          d('distanceScoreMultiplier', base.distanceScoreMultiplier),
      ratingScoreMultiplier: d('ratingScoreMultiplier', base.ratingScoreMultiplier),
      matchScoreMultiplier: d('matchScoreMultiplier', base.matchScoreMultiplier),
      serviceScoreMultiplier:
          d('serviceScoreMultiplier', base.serviceScoreMultiplier),
      serviceScoreCap: i('serviceScoreCap', base.serviceScoreCap),
      priceScoreMultiplier: d('priceScoreMultiplier', base.priceScoreMultiplier),
      distancePenaltyMultiplier:
          d('distancePenaltyMultiplier', base.distancePenaltyMultiplier),
    );
  }
}

