import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CaregiverProfileScreen extends StatelessWidget {
  const CaregiverProfileScreen({super.key});

  static const List<_MenuRow> _menuRows = [
    _MenuRow(icon: Icons.edit, label: 'Edit Profile'),
    _MenuRow(icon: Icons.bar_chart, label: 'Earnings & Reports'),
    _MenuRow(icon: Icons.schedule, label: 'Schedule'),
    _MenuRow(icon: Icons.help_center, label: 'Help Center'),
    _MenuRow(icon: Icons.question_answer, label: 'FAQ'),
    _MenuRow(icon: Icons.description, label: 'Terms of Service'),
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your profile')),
      );
    }

    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: Center(
              child: Text('Unable to load profile: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() ?? {};
        final name = data['name'] as String? ?? 'Caregiver';
        final role = data['role'] as String? ?? 'Caregiver';
        final photoUrl = data['photoUrl'] as String?;
        final availability = data['availability'] as bool? ?? false;
        final certifications = _stringListFromField(data['certifications']);
        final services = _stringListFromField(data['services']);
        final rating = (data['rating'] as num?)?.toDouble();
        final jobsCompleted = (data['jobsCompleted'] as num?)?.toInt() ?? 0;

        return Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(
                context,
                name: name,
                role: role,
                photoUrl: photoUrl,
                availability: availability,
                caregiverId: user.uid,
              ),
              const SizedBox(height: 24),
              _buildStats(
                theme: Theme.of(context),
                jobsCompleted: jobsCompleted,
                rating: rating,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Certifications'),
              const SizedBox(height: 12),
              _buildChipSection(
                items: certifications,
                fallbackLabel: 'No certifications yet',
                theme: Theme.of(context),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Services Offered'),
              const SizedBox(height: 12),
              _buildChipSection(
                items: services,
                fallbackLabel: 'No services listed yet',
                theme: Theme.of(context),
                accent: true,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Menu'),
              const SizedBox(height: 12),
              ..._menuRows.map((row) => _buildMenuCard(context, row)),
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () => _handleLogout(context),
                child: const Text('Logout'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String name,
    required String role,
    String? photoUrl,
    required bool availability,
    required String caregiverId,
  }) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl == null || photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 32)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  availability ? 'Available' : 'Offline',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Switch(
                  value: availability,
                  onChanged: (value) => _updateAvailability(caregiverId, value),
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white54,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats({
    required ThemeData theme,
    required int jobsCompleted,
    required double? rating,
  }) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Total Jobs',
            value: jobsCompleted.toString(),
            color: theme.colorScheme.primaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Rating',
            value: rating != null ? rating.toStringAsFixed(1) : '-',
            color: theme.colorScheme.secondaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Hours Worked',
            value: '-',
            color: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
  );

  Widget _buildChipSection({
    required List<String> items,
    required String fallbackLabel,
    required ThemeData theme,
    bool accent = false,
  }) {
    if (items.isEmpty) {
      return Chip(
        label: Text(fallbackLabel),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (label) => Chip(
              label: Text(label),
              backgroundColor: accent
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMenuCard(BuildContext context, _MenuRow row) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(row.icon, color: Theme.of(context).colorScheme.primary),
        title: Text(row.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _handleMenuTap(context, row.label),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  void _handleMenuTap(BuildContext context, String label) {
    if (label == 'Edit Profile') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This section is coming soon.')),
    );
  }

  Future<void> _updateAvailability(String caregiverId, bool value) {
    return FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId)
        .update({'availability': value});
  }

  static List<String> _stringListFromField(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .toList();
    }
    return [];
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class CaregiverProfileEditScreen extends StatelessWidget {
  const CaregiverProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: const Center(
        child: Text('Profile editing is not implemented yet.'),
      ),
    );
  }
}
