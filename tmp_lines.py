from pathlib import Path
lines = Path('lib/screens/caregiver/profile/caregiver_profile_screen.dart').read_text().splitlines()
for i in range(460, 520):
    if i < len(lines):
        print(f"{i+1:04d}: {lines[i]}")
