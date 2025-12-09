from pathlib import Path
path = Path('lib/screens/user/booking/booking_person_screen.dart')
with path.open() as f:
    for i,line in enumerate(f,1):
        if 720 <= i <= 790:
            print(f'{i}: {line.rstrip()}')
