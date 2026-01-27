import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_screen.dart' show activityBackgroundColor;
import 'admin_reviews_edit_screen.dart';
import 'admin_ui.dart';

class AdminReviewsScreen extends StatelessWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('services')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: buildProfileStyleAppBar(
        title: 'Services',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _AdminGoldAddButton(
              label: 'Add Service',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminReviewsEditScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return buildAdminEmptyState(
                    icon: Icons.rate_review_outlined,
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
                    icon: Icons.rate_review_outlined,
                    title: 'No services yet',
                    subtitle: 'New services will appear here.',
                  );
                }

                return ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = docs[index].data();
                    final name = ((data['name'] as String?) ?? '').trim();
                    final description = ((data['description'] as String?) ?? '')
                        .trim();
                    final imageUrl = ((data['imageUrl'] as String?) ?? '')
                        .trim();
                    final price = (data['price'] as num?)?.toDouble();
                    final per = ((data['per'] as String?) ?? '')
                        .trim()
                        .toLowerCase();

                    final priceLabel = price == null
                        ? ''
                        : per.isNotEmpty
                        ? 'RM ${price.toStringAsFixed(2)} / $per'
                        : 'RM ${price.toStringAsFixed(2)}';

                    return _ServiceCard(
                      indexNumber: index + 1,
                      id: doc.id,
                      name: name.isNotEmpty ? name : 'Service',
                      priceLabel: priceLabel,
                      description: description,
                      photoUrl: imageUrl.isNotEmpty ? imageUrl : null,
                      onEdit: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AdminReviewsEditScreen(serviceId: doc.id),
                          ),
                        );
                      },
                      onDelete: () async {
                        await FirebaseFirestore.instance
                            .collection('services')
                            .doc(doc.id)
                            .delete();
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

class _AdminGoldAddButton extends StatelessWidget {
  const _AdminGoldAddButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: adminAccentGold,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: adminAccentGold.withValues(alpha: 0.55),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.indexNumber,
    required this.id,
    required this.name,
    required this.priceLabel,
    required this.description,
    required this.photoUrl,
    required this.onEdit,
    required this.onDelete,
  });

  final int indexNumber;
  final String id;
  final String name;
  final String priceLabel;
  final String description;
  final String? photoUrl;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.shade300;
    const double borderWidth = 1.0;
    const cardColor = Colors.white;
    const horizontalPadding = 12.0;
    const verticalPadding = 8.0;
    const dividerPadding = 6.0;

    final cardContent = Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            spreadRadius: 0.5,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    DefaultProfileAvatar(
                      radius: 26,
                      photoUrl: photoUrl,
                      label: name,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (priceLabel.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          priceLabel.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                            height: 1.2,
                          ),
                        ),
                      ],
                      if (description.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: dividerPadding),
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: Container(
                  height: 1.2,
                  color: Colors.black.withAlpha(20),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _ServiceActionButton(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    isPrimary: true,
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(16),
      child: cardContent,
    );
  }
}

class _ServiceActionButton extends StatelessWidget {
  const _ServiceActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final background = isPrimary
        ? (isEnabled ? const Color(0xFF00A8A7) : Colors.grey[400])
        : Colors.white;
    final foreground = isPrimary
        ? Colors.white
        : Colors.black87.withValues(alpha: isEnabled ? 1 : 0.35);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary
                ? Colors.transparent
                : Colors.grey.withValues(alpha: isEnabled ? 0.35 : 0.2),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
