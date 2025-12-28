from pathlib import Path
lines=Path('lib/screens/user/booking/booking_caregiver_screen.dart').read_text().splitlines()
for i in range(250,340):
    print(str(i+1)+': '+lines[i])
