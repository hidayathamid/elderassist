import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'register_screen.dart';

class TouchdownScreen extends StatefulWidget {
  const TouchdownScreen({super.key});

  @override
  State<TouchdownScreen> createState() => _TouchdownScreenState();
}

class _TouchdownScreenState extends State<TouchdownScreen> {
  final PageController _pageController = PageController();
  int _activePage = 0;

  static const List<_TouchdownSlide> _slides = [
    _TouchdownSlide(
      imagePath: 'assets/images/onboarding_caregivers.png',
      title: 'Welcome to ElderAssist',
      subtitle: 'Care where you are',
      description:
          'Get flexible, personalised home and community-based support from qualified, locally trained caregivers.',
      backgroundColor: Color(0xFFFDF3E1),
    ),
    _TouchdownSlide(
      imagePath: 'assets/images/onboarding_emergency.png',
      title: 'Rapid Emergency Aid',
      subtitle: 'Help within minutes',
      description:
          'Trigger emergency requests instantly and we will match nearby caregivers who are ready to respond.',
      backgroundColor: Color(0xFFE5F2FF),
    ),
    _TouchdownSlide(
      imagePath: 'assets/images/onboarding_companions.png',
      title: 'Trusted Companionship',
      subtitle: 'Support that feels human',
      description:
          'From daily tasks to emotional support, our care team focuses on dignity, independence, and comfort.',
      backgroundColor: Color(0xFFF2EEFF),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final Color primaryColor = const Color(0xFFF4B63D);
    const Color darkText = Color(0xFF1F1F1F);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double visualHeight = constraints.maxHeight * 0.58;
                    return PageView.builder(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (value) =>
                          setState(() => _activePage = value),
                      itemCount: _slides.length,
                      itemBuilder: (context, index) {
                        final slideItem = _slides[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: visualHeight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: slideItem.backgroundColor,
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                padding: const EdgeInsets.all(24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    slideItem.imagePath,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    width: double.infinity,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              slideItem.title,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                color: darkText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              slideItem.subtitle,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              slideItem.description,
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const Spacer(),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: _activePage == index ? 18 : 6,
                    decoration: BoxDecoration(
                      color: _activePage == index
                          ? primaryColor
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Get started'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: darkText,
                    side: const BorderSide(color: Color(0xFFE1E1E1)),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Log in'),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Already part of the caregiver team? ',
                      style: TextStyle(color: Colors.black87),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Log in',
                        style: TextStyle(
                          color: Color(0xFF00A8A7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      ' here.',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TouchdownSlide {
  final String imagePath;
  final String title;
  final String subtitle;
  final String description;
  final Color backgroundColor;

  const _TouchdownSlide({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.backgroundColor,
  });
}
