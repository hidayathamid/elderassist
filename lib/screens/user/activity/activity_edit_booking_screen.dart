import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:emergencies_disability_assistance_app/models/activity_booking.dart';

class ActivityEditBookingScreen extends StatefulWidget {
  const ActivityEditBookingScreen({super.key, required this.booking});

  final ActivityBooking booking;

  @override
  State<ActivityEditBookingScreen> createState() =>
      _ActivityEditBookingScreenState();
}

class _ActivityEditBookingScreenState
    extends State<ActivityEditBookingScreen> {
  late TextEditingController _notesController;
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _isSaving = false;
  String _caregiverName = 'Caregiver';

  @override
  void initState() {
    super.initState();
    _notesController =
        TextEditingController(text: widget.booking.notes ?? '');
    _selectedDate = _parseDate(widget.booking.date);
    _startTime = _parseTime(widget.booking.startTime);
    _endTime = _parseTime(widget.booking.endTime);
    _loadCaregiverName();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DateTime _parseDate(String value) {
    try {
      final parts = value.split('-');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (_) {}
    return DateTime.now();
  }

  TimeOfDay _parseTime(String value) {
    try {
      final parts = value.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 9;
        final minute = int.tryParse(parts[1]) ?? 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime(TimeOfDay initial, ValueChanged<TimeOfDay> onPicked) async {
    final time = await showTimePicker(context: context, initialTime: initial);
    if (time != null) {
      onPicked(time);
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final updates = {
      'notes': _notesController.text.trim(),
      'scheduledDate': _formatDate(_selectedDate),
      'startTime': _formatTime(_startTime),
      'endTime': _formatTime(_endTime),
    };

    final bookingRef =
        FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id);

    try {
      await bookingRef.update(updates);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking updated')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update booking: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _loadCaregiverName() async {
    final doc = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(widget.booking.caregiverId)
        .get();
    final name = doc.data()?['name'] as String?;
    if (name != null && name.isNotEmpty && mounted) {
      setState(() => _caregiverName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Booking')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              title: const Text('Person'),
              subtitle: Text(widget.booking.personName),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              title: const Text('Caregiver'),
              subtitle: Text(_caregiverName),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Date'),
            subtitle: Text(
                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Start time'),
            subtitle: Text(_startTime.format(context)),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(_startTime, (picked) {
              setState(() => _startTime = picked);
            }),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('End time'),
            subtitle: Text(_endTime.format(context)),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(_endTime, (picked) {
              setState(() => _endTime = picked);
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style:
                ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
