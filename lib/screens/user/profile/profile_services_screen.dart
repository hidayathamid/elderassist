import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _selectedServiceColor = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);
const Color _profileCardBorder = Color(0xFFD7DCE3);

class ProfileServicesScreen extends StatefulWidget {
  final bool useServiceOfferedTitle;

  const ProfileServicesScreen({super.key, this.useServiceOfferedTitle = false});

  @override
  State<ProfileServicesScreen> createState() => _ProfileServicesScreenState();
}

class _ProfileServicesScreenState extends State<ProfileServicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  bool _selectionInitialized = false;
  final Set<String> _selectedLocal = <String>{};
  final Set<String> _expandedServiceIds = <String>{};

  static String _normalizeServiceName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _caregiverStream(String uid) =>
      FirebaseFirestore.instance.collection('caregivers').doc(uid).snapshots();

  List<String> _extractPreferences(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['servicePreferences'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return [];
  }

  Future<void> _togglePreference(
    String uid,
    String option,
    List<String> current, {
    required bool isCaregiver,
  }) async {
    final normalizedOption = _normalizeServiceName(option);
    final updated = <String>[];
    bool exists = false;
    for (final raw in current) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (_normalizeServiceName(trimmed) == normalizedOption) {
        exists = true;
        continue; // remove any existing variant when toggling
      }
      updated.add(trimmed);
    }
    if (!exists) {
      // Always store canonical value from the services catalog.
      updated.add(option.trim());
    }
    final ref = FirebaseFirestore.instance.collection(
      isCaregiver ? 'caregivers' : 'users',
    ).doc(uid);
    const field = 'servicePreferences';
    await ref.set({field: updated}, SetOptions(merge: true));
  }

  List<String> _extractCaregiverServices(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['servicePreferences'] ?? data['services'];
    if (raw is Iterable) {
      return raw.whereType<String>().toList();
    }
    return [];
  }

  void _updateFilter(String value) {
    setState(() => _filter = value.trim());
  }

  void _syncSelectionFromRemote(List<String> remote) {
    if (_selectionInitialized) return;
    _selectedLocal
      ..clear()
      ..addAll(
        remote
            .map(_normalizeServiceName)
            .where((e) => e.isNotEmpty),
      );
    _selectionInitialized = true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please sign in to view service preferences.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _profileDarkText,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.useServiceOfferedTitle
              ? 'Service Offered'
              : 'Service Preferences',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: _profileDarkText,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream(user.uid),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load preferences: ${userSnapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _caregiverStream(user.uid),
            builder: (context, caregiverSnapshot) {
              if (caregiverSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Unable to load caregiver services: ${caregiverSnapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              final isCaregiver =
                  caregiverSnapshot.hasData && caregiverSnapshot.data!.exists;
              final caregiverServices = _extractCaregiverServices(
                caregiverSnapshot.data?.data(),
              );
              final preferences = isCaregiver
                  ? caregiverServices
                  : _extractPreferences(userSnapshot.data!.data());

              _syncSelectionFromRemote(preferences);

              final servicesStream = FirebaseFirestore.instance
                  .collection('services')
                  .orderBy('name')
                  .snapshots();

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _updateFilter,
                            style: const TextStyle(fontSize: 11),
                            decoration: InputDecoration(
                              hintText: 'Search services',
                              hintStyle: const TextStyle(fontSize: 11),
                              prefixIcon: const Icon(Icons.search, size: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                                borderSide: BorderSide(
                                  color: Colors.black,
                                  width: 1.1,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            _searchController.clear();
                            _updateFilter('');
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return _accentGold.withValues(alpha: 0.8);
                              }
                              return _accentGold;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return Colors.grey.shade600;
                              }
                              return Colors.black;
                            }),
                            elevation: WidgetStateProperty.resolveWith<double>((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return 0;
                              }
                              return 0;
                            }),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            textStyle: WidgetStateProperty.all(
                              const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: servicesStream,
                      builder: (context, servicesSnapshot) {
                        if (servicesSnapshot.hasError) {
                          return Center(
                            child: Text(
                              'Unable to load services: ${servicesSnapshot.error}',
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }
                        if (!servicesSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final all = servicesSnapshot.data!.docs
                            .map(_ServiceCatalogEntry.fromDoc)
                            .where((e) => e.name.isNotEmpty)
                            .toList()
                          ..sort((a, b) => a.name.toLowerCase().compareTo(
                                b.name.toLowerCase(),
                              ));

                        final query = _filter.trim().toLowerCase();
                        final filtered = query.isEmpty
                            ? all
                            : all
                                .where(
                                  (e) =>
                                      e.name.toLowerCase().contains(query) ||
                                      e.description.toLowerCase().contains(query),
                                )
                                .toList();

                        if (filtered.isEmpty) {
                          return SizedBox(
                            height: 220,
                            child: Center(
                              child: Text(
                                'No services found',
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        }

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 12.0;
                            final maxWidth = constraints.maxWidth;
                            final cellWidth = ((maxWidth - spacing) / 2).clamp(
                              1.0,
                              double.infinity,
                            );
                            // Keep a stable card ratio without compressing via FittedBox.
                            final childAspectRatio = cellWidth / 238.0;

                        return GridView.builder(
                          itemCount: filtered.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                childAspectRatio: childAspectRatio,
                              ),
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            final entryNorm =
                                _normalizeServiceName(entry.name);
                            final remoteSelected = preferences
                                .map(_normalizeServiceName)
                                .contains(entryNorm);
                            final isSelected = _selectedLocal.contains(entryNorm) ||
                                remoteSelected;
                            final isExpanded =
                                _expandedServiceIds.contains(entry.id);
                            return _ServiceTile(
                              entry: entry,
                              selected: isSelected,
                              expanded: isExpanded,
                              onToggleSelected: () async {
                                setState(() {
                                  if (isSelected) {
                                    _selectedLocal.remove(entryNorm);
                                  } else {
                                    _selectedLocal.add(entryNorm);
                                  }
                                });
                                await _togglePreference(
                                  user.uid,
                                  entry.name,
                                      preferences,
                                      isCaregiver: isCaregiver,
                                    );
                                  },
                                  onToggleExpanded: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedServiceIds.remove(entry.id);
                                      } else {
                                        _expandedServiceIds.add(entry.id);
                                      }
                                    });
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ServiceCatalogEntry {
  const _ServiceCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.per,
  });

  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final double? price;
  final String per;

  static _ServiceCatalogEntry fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final name = ((data['name'] as String?) ?? '').trim();
    final description = ((data['description'] as String?) ?? '').trim();
    final imageUrl = ((data['imageUrl'] as String?) ?? '').trim();
    final price = (data['price'] as num?)?.toDouble();
    final per = ((data['per'] as String?) ?? '').trim().toLowerCase();
    return _ServiceCatalogEntry(
      id: doc.id,
      name: name,
      description: description,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
      price: price,
      per: per,
    );
  }

  String get priceLabel {
    final value = price;
    if (value == null) return '';
    final base = 'RM ${value.toStringAsFixed(2)}';
    if (per.trim().isEmpty) return base;
    return '$base / ${per.trim()}';
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.entry,
    required this.selected,
    required this.expanded,
    required this.onToggleSelected,
    required this.onToggleExpanded,
  });

  final _ServiceCatalogEntry entry;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? _selectedServiceColor : _profileCardBorder;
    final shadowColor = Colors.black.withValues(alpha: selected ? 0.10 : 0.06);

    return GestureDetector(
      onTap: onToggleSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: selected ? 1.2 : 1.0),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          child: expanded
              ? _ServiceTileBack(
                  key: ValueKey('back_${entry.id}'),
                  entry: entry,
                  onBack: onToggleExpanded,
                )
              : _ServiceTileFront(
                  key: ValueKey('front_${entry.id}'),
                  entry: entry,
                  onDetails: onToggleExpanded,
                ),
        ),
      ),
    );
  }
}

class _ServiceTileFront extends StatelessWidget {
  const _ServiceTileFront({
    super.key,
    required this.entry,
    required this.onDetails,
  });

  final _ServiceCatalogEntry entry;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(18),
          ),
          child: SizedBox(
            height: 88,
            width: double.infinity,
            child: entry.imageUrl == null
                ? Container(
                    color: const Color(0xFFF2F4F7),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      color: _selectedServiceColor,
                      size: 28,
                    ),
                  )
                : Image.network(
                    entry.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => Container(
                      color: const Color(0xFFF2F4F7),
                      child: const Icon(
                        Icons.medical_services_outlined,
                        color: _selectedServiceColor,
                        size: 28,
                      ),
                    ),
                  ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.priceLabel.isNotEmpty
                      ? entry.priceLabel
                      : 'Price unavailable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: onDetails,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 16),
                        SizedBox(width: 6),
                        Text('Details'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceTileBack extends StatelessWidget {
  const _ServiceTileBack({
    super.key,
    required this.entry,
    required this.onBack,
  });

  final _ServiceCatalogEntry entry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final description = entry.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        description.isNotEmpty
                            ? description
                            : 'No details available.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: Colors.black.withValues(alpha: 0.70),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _profileDarkText,
                      side: BorderSide(color: Colors.grey.shade300, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                        SizedBox(width: 6),
                        Text('Back'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
