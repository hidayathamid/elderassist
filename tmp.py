from pathlib import Path
lines=Path('lib/screens/caregiver/profile/caregiver_profile_screen.dart').read_text().splitlines()
for i in range(60,90):
    print(str(i+1)+': '+lines[i])
