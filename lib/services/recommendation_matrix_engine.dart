import 'package:cloud_firestore/cloud_firestore.dart';

class RecommendationMatrixEngine {
  const RecommendationMatrixEngine._();

  static List<RecommendationMatrixRule> parseRulesSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final rules = <RecommendationMatrixRule>[];
    for (final doc in snapshot.docs) {
      if (doc.id == 'current') continue;
      final rule = RecommendationMatrixRule.tryParse(doc.data());
      if (rule != null) rules.add(rule);
    }
    rules.sort(RecommendationMatrixRule.compare);
    return rules;
  }

  static int recommendationClass({
    required List<RecommendationMatrixRule> rules,
    required double distanceKm,
    required double priceValue,
    required int matchCount,
    required int requestedServiceCount,
    required int caregiverServiceCount,
    required double caregiverRating,
    double clientBudget = 150.0,
  }) {
    final normalizedBudget = clientBudget.clamp(10.0, 150.0);
    if (rules.isEmpty) return 3;

    final features = RecommendationMatrixFeatures.from(
      distanceKm: distanceKm,
      caregiverPrice: priceValue,
      clientBudget: normalizedBudget,
      caregiverRating: caregiverRating,
      matchCount: matchCount,
      requestedServiceCount: requestedServiceCount,
      caregiverServiceCount: caregiverServiceCount,
    );

    final exact = rules.firstWhere(
      (r) => r.matches(features),
      orElse: () => const RecommendationMatrixRule.empty(),
    );
    if (exact.isValid) return exact.recommendationClass;

    RecommendationMatrixRule? best;
    var bestDistance = 1 << 30;
    for (final rule in rules) {
      final d = rule.distanceTo(features);
      if (d < bestDistance) {
        bestDistance = d;
        best = rule;
        continue;
      }
      if (d == bestDistance &&
          best != null &&
          rule.recommendationClass < best.recommendationClass) {
        best = rule;
      }
    }
    return best?.recommendationClass ?? 3;
  }
}

class RecommendationMatrixFeatures {
  const RecommendationMatrixFeatures({
    required this.ratingLevel,
    required this.distanceLevel,
    required this.matchLevel,
    required this.priceGapLevel,
    required this.serviceCountLevel,
  });

  final int ratingLevel;
  final int priceGapLevel;
  final int distanceLevel;
  final int matchLevel;
  final int serviceCountLevel;

  static RecommendationMatrixFeatures from({
    required double distanceKm,
    required double caregiverPrice,
    required double clientBudget,
    required double caregiverRating,
    required int matchCount,
    required int requestedServiceCount,
    required int caregiverServiceCount,
  }) {
    final priceGapLevel = () {
      if (clientBudget <= 0) return 3;
      if (caregiverPrice <= clientBudget) return 1;
      final overPercent = ((caregiverPrice - clientBudget) / clientBudget) * 100.0;
      if (overPercent <= 5) return 2;
      if (overPercent <= 15) return 3;
      if (overPercent <= 30) return 4;
      return 5;
    }();

    final ratingLevel = () {
      if (caregiverRating >= 4.8) return 1;
      if (caregiverRating >= 4.5) return 2;
      if (caregiverRating >= 4.0) return 3;
      if (caregiverRating >= 3.5) return 4;
      return 5;
    }();

    final distanceLevel = () {
      if (distanceKm <= 5) return 1;
      if (distanceKm <= 15) return 2;
      if (distanceKm <= 25) return 3;
      if (distanceKm <= 40) return 4;
      return 5;
    }();

    final matchLevel = () {
      if (requestedServiceCount <= 0) return 3;
      final ratio = matchCount / requestedServiceCount;
      if (ratio >= 1.0) return 1;
      if (ratio >= 0.66) return 2;
      if (ratio >= 0.34) return 3;
      if (ratio > 0.0) return 4;
      return 5;
    }();

    final serviceCountLevel = () {
      if (caregiverServiceCount >= 5) return 1;
      if (caregiverServiceCount >= 3) return 2;
      if (caregiverServiceCount >= 2) return 3;
      if (caregiverServiceCount >= 1) return 4;
      return 5;
    }();

    return RecommendationMatrixFeatures(
      ratingLevel: ratingLevel,
      distanceLevel: distanceLevel,
      matchLevel: matchLevel,
      priceGapLevel: priceGapLevel,
      serviceCountLevel: serviceCountLevel,
    );
  }
}

class RecommendationMatrixRule {
  const RecommendationMatrixRule({
    required this.ratingLevel,
    required this.distanceLevel,
    required this.matchLevel,
    required this.priceGapLevel,
    required this.serviceCountLevel,
    required this.recommendationClass,
  });

  final int ratingLevel;
  final int distanceLevel;
  final int matchLevel;
  final int priceGapLevel;
  final int serviceCountLevel;
  final int recommendationClass;

  bool get isValid =>
      ratingLevel > 0 &&
      distanceLevel > 0 &&
      matchLevel > 0 &&
      priceGapLevel > 0 &&
      serviceCountLevel > 0 &&
      recommendationClass > 0;

  bool matches(RecommendationMatrixFeatures features) {
    return ratingLevel == features.ratingLevel &&
        distanceLevel == features.distanceLevel &&
        matchLevel == features.matchLevel &&
        priceGapLevel == features.priceGapLevel &&
        serviceCountLevel == features.serviceCountLevel;
  }

  int distanceTo(RecommendationMatrixFeatures features) {
    return (ratingLevel - features.ratingLevel).abs() +
        (distanceLevel - features.distanceLevel).abs() +
        (matchLevel - features.matchLevel).abs() +
        (priceGapLevel - features.priceGapLevel).abs() +
        (serviceCountLevel - features.serviceCountLevel).abs();
  }

  static RecommendationMatrixRule? tryParse(Map<String, dynamic> data) {
    int? readInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final ratingLevel = readInt(data['rating_level'] ?? data['ratingLevel']);
    final distanceLevel = readInt(data['distance_level'] ?? data['distanceLevel']);
    final matchLevel = readInt(data['match_level'] ?? data['matchLevel']);
    final priceGapLevel = readInt(
      data['price_gap_level'] ?? data['priceGapLevel'],
    );
    final serviceCountLevel = readInt(
      data['service_count_level'] ?? data['serviceCountLevel'],
    );
    final recommendationClass = readInt(
      data['recommendation_class'] ?? data['recommendationClass'] ?? data['classLevel'],
    );

    if (ratingLevel == null ||
        distanceLevel == null ||
        matchLevel == null ||
        priceGapLevel == null ||
        serviceCountLevel == null ||
        recommendationClass == null) {
      return null;
    }

    final safeClass = recommendationClass.clamp(1, 3);
    return RecommendationMatrixRule(
      ratingLevel: ratingLevel.clamp(1, 5),
      distanceLevel: distanceLevel.clamp(1, 5),
      matchLevel: matchLevel.clamp(1, 5),
      priceGapLevel: priceGapLevel.clamp(1, 5),
      serviceCountLevel: serviceCountLevel.clamp(1, 5),
      recommendationClass: safeClass,
    );
  }

  static int compare(RecommendationMatrixRule a, RecommendationMatrixRule b) {
    final c0 = a.recommendationClass.compareTo(b.recommendationClass);
    if (c0 != 0) return c0;
    final c1 = a.ratingLevel.compareTo(b.ratingLevel);
    if (c1 != 0) return c1;
    final c2 = a.matchLevel.compareTo(b.matchLevel);
    if (c2 != 0) return c2;
    final c3 = a.priceGapLevel.compareTo(b.priceGapLevel);
    if (c3 != 0) return c3;
    final c4 = a.distanceLevel.compareTo(b.distanceLevel);
    if (c4 != 0) return c4;
    return a.serviceCountLevel.compareTo(b.serviceCountLevel);
  }

  const RecommendationMatrixRule.empty()
      : ratingLevel = 0,
        distanceLevel = 0,
        matchLevel = 0,
        priceGapLevel = 0,
        serviceCountLevel = 0,
        recommendationClass = 0;
}
