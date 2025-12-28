import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../constants/service_options.dart';
import '../../../widgets/service_chip.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _selectedServiceColor = Color(0xFF00A8A7);
const Color _accentGold = Color(0xFFF4B63D);

class ProfileServicesScreen extends StatefulWidget {
  final bool useServiceOfferedTitle;

  const ProfileServicesScreen({super.key, this.useServiceOfferedTitle = false});

  @override
  State<ProfileServicesScreen> createState() => _ProfileServicesScreenState();
}

class _ProfileServicesScreenState extends State<ProfileServicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

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
    final updated = List<String>.from(current);
    if (updated.contains(option)) {
      updated.remove(option);
    } else {
      updated.add(option);
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

  List<String> _visibleOptions() {
    if (_filter.isEmpty) return kServiceOptions;
    final query = _filter.toLowerCase();
    return kServiceOptions
        .where((option) => option.toLowerCase().contains(query))
        .toList();
  }

  void _updateFilter(String value) {
    setState(() => _filter = value.trim());
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
              final visible = _visibleOptions();

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
                                return _accentGold.withOpacity(0.8);
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
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      children: visible.map((option) {
                        final selected = preferences.contains(option);
                        return ServiceChip(
                          label: option,
                          selected: selected,
                          onTap: () => _togglePreference(
                            user.uid,
                            option,
                            preferences,
                            isCaregiver: isCaregiver,
                          ),
                        );
                      }).toList(),
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
