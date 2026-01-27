import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class AdminServicesScreen extends StatelessWidget {
  const AdminServicesScreen({super.key});

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const <String>[];
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('caregivers')
        .orderBy('created_at', descending: true)
        .limit(80)
        .snapshots();

    return AdminTabScaffold(
      title: 'Services',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return buildAdminEmptyState(
              icon: Icons.settings_outlined,
              title: 'Unable to load services',
              subtitle: 'Please try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return buildAdminEmptyState(
              icon: Icons.settings_outlined,
              title: 'No caregivers yet',
              subtitle: 'Services will appear once caregivers are registered.',
            );
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final name = ((data['name'] as String?) ?? '').trim();
              final services = _stringList(
                data['servicePreferences'] ?? data['services'],
              );
              final availability = (data['availability'] as bool?) ?? true;

              return _AdminServicesTile(
                indexNumber: index + 1,
                name: name.isNotEmpty ? name : 'Caregiver',
                availability: availability,
                services: services,
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminServicesTile extends StatelessWidget {
  const _AdminServicesTile({
    required this.indexNumber,
    required this.name,
    required this.availability,
    required this.services,
  });

  final int indexNumber;
  final String name;
  final bool availability;
  final List<String> services;

  @override
  Widget build(BuildContext context) {
    final availabilityLabel = availability ? 'AVAILABLE' : 'OFF';
    final availabilityColor = availability
        ? const Color(0xFF00A8A7)
        : Colors.black45;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A8A7).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF00A8A7).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      size: 24,
                      color: Color(0xFF00A8A7),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A8A7),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        indexNumber.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: availabilityColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: availabilityColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  availabilityLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    color: availabilityColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (services.isEmpty)
            Text(
              'No services listed',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final service in services.take(8))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: adminAccentGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: adminAccentGold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      service,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: Colors.black,
                      ),
                    ),
                  ),
                if (services.length > 8)
                  Text(
                    '+${services.length - 8} more',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
