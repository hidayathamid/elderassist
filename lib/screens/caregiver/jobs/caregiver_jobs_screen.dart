import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'caregiver_job_details_screen.dart';

class CaregiverJobsScreen extends StatefulWidget {
  const CaregiverJobsScreen({super.key});

  @override
  State<CaregiverJobsScreen> createState() => _CaregiverJobsScreenState();
}

class _CaregiverJobsScreenState extends State<CaregiverJobsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const tabs = ['Upcoming', 'History'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Jobs')),
        body: const Center(child: Text('Please sign in to view jobs')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('caregivers')
            .doc(user.uid)
            .collection('assignedBookings')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final jobs = docs.map((doc) => _CaregiverJob.fromDoc(doc)).toList();
          final upcoming = jobs.where((j) {
            final status = j.status.toUpperCase();
            return status == 'PENDING' ||
                status == 'ASSIGNED' ||
                status == 'ONGOING';
          }).toList();
          final history = jobs.where((j) {
            final status = j.status.toUpperCase();
            return status == 'COMPLETED' || status == 'CANCELLED';
          }).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _JobList(jobs: upcoming),
              _JobList(jobs: history),
            ],
          );
        },
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs});

  final List<_CaregiverJob> jobs;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const Center(child: Text('No jobs'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ListTile(
            leading: CircleAvatar(child: Text(job.personName.isNotEmpty ? job.personName[0] : '?')),
            title: Row(
              children: [
                Expanded(
                  child: Text(job.personName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Chip(
                  label: Text(job.status),
                  backgroundColor: _statusColor(job.status).withValues(alpha: 0.15),
                ),
              ],
            ),
            subtitle: Text('${job.scheduledDate} | ${job.startTime} - ${job.endTime}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CaregiverJobDetailsScreen(bookingId: job.bookingId),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Color _statusColor(String status) {
  switch (status.toUpperCase()) {
    case 'ONGOING':
      return Colors.blue;
    case 'ARRIVED':
      return Colors.green;
    case 'COMPLETED':
      return Colors.grey;
    case 'CANCELLED':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

class _CaregiverJob {
  const _CaregiverJob({
    required this.bookingId,
    required this.userId,
    required this.personName,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.price,
    required this.notes,
    required this.caregiverId,
  });

  final String bookingId;
  final String userId;
  final String personName;
  final String scheduledDate;
  final String startTime;
  final String endTime;
  final String status;
  final String price;
  final String notes;
  final String caregiverId;

  factory _CaregiverJob.fromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _CaregiverJob(
      bookingId: doc.id,
      userId: (data['userId'] as String?) ?? '',
      personName: (data['personName'] as String?) ?? 'Client',
      scheduledDate: (data['scheduledDate'] as String?) ?? '',
      startTime: (data['startTime'] as String?) ?? '',
      endTime: (data['endTime'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'PENDING',
      price: (data['price'] as Object?)?.toString() ?? 'RM 0',
      notes: (data['notes'] as String?) ?? '',
      caregiverId: (data['caregiverId'] as String?) ?? doc.reference.parent.parent?.id ?? '',
    );
  }
}
