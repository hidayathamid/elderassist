from pathlib import Path
path = Path('lib/screens/user/booking/booking_caregiver_screen.dart')
with path.open() as f:
    for i, line in enumerate(f, 1):
        if 800 <= i <= 860:
            print(f'{i}: {line.rstrip()}')
