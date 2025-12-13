import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';

import 'sos_countdown_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

const Color _sosAppBarText = Color(0xFF1B1D29);

class SosActivateScreen extends StatelessWidget {
  const SosActivateScreen({super.key});

  void _startCountdown(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SosCountdownScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildProfileStyleAppBar(title: 'Emergency Assistance'),
      body: Padding(
        padding: kHorizontalScreenPadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Trigger an emergency SOS alert so nearby caregivers can respond quickly.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.colorScheme.error,
                      theme.colorScheme.primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.error.withValues(alpha: 153),
                      blurRadius: 18,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'SOS',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Stay calm and provide your location details once responders are on the way.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startCountdown(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Activate SOS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
