import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SosFindingScreen extends StatefulWidget {
  const SosFindingScreen({super.key, required this.sosId});

  final String sosId;

  @override
  State<SosFindingScreen> createState() => _SosFindingScreenState();
}

class _SosFindingScreenState extends State<SosFindingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _dotsController.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return 'Accepted';
      case 'DECLINED':
      case 'REJECTED':
        return 'Declined';
      case 'PENDING':
        return 'Pending';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Finding caregivers')),
      body: Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.search, size: 48),
          const SizedBox(height: 12),
          Text(
            'Searching nearby caregivers...',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _dotsController,
            builder: (_, __) {
              final progress = (_dotsController.value * 3).floor();
              final dots = List.generate(
                3,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withOpacity(
                      index == progress % 3 ? 1 : 0.3,
                    ),
                  ),
                ),
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dots,
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Notifying caregivers in your vicinity...',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('sos')
                  .doc(widget.sosId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Unable to load responders: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: CircularProgressIndicator());
                }

                final status =
                    (snapshot.data!.data()?['status'] as String?)?.toUpperCase() ??
                        'FINDING';

                if (status == 'NO_RESPONDER') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.amber,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No caregivers were available right now. Please try again later.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('sos')
                      .doc(widget.sosId)
                      .collection('responders')
                      .orderBy('distanceKm')
                      .snapshots(),
                  builder: (context, responders) {
                    if (responders.hasError) {
                      return Center(
                        child: Text(
                            'Unable to load responders: ${responders.error}'),
                      );
                    }

                    if (!responders.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = responders.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('Waiting for responders...'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final responderData = docs[index].data();
                        final caregiverName = responderData['caregiverName']
                                as String? ??
                            'Caregiver';
                        final photoUrl =
                            responderData['caregiverPhoto'] as String?;
                        final distanceKm =
                            (responderData['distanceKm'] as num?)?.toDouble();
                        final statusValue = (responderData['status']
                                    as String?)
                                ?.toUpperCase() ??
                            'PENDING';
                        final initials = caregiverName.isNotEmpty
                            ? caregiverName.substring(0, 1)
                            : '?';

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              radius: 26,
                              backgroundImage: (photoUrl != null &&
                                      photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? Text(initials)
                                  : null,
                            ),
                            title: Text(
                              caregiverName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  distanceKm != null
                                      ? '${distanceKm.toStringAsFixed(1)} km away'
                                      : 'Distance unavailable',
                                ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _statusLabel(statusValue),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
