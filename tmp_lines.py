from pathlib import Path
lines=Path('lib/screens/user/booking/booking_caregiver_screen.dart').read_text().splitlines()
for i,line in enumerate(lines):
    if 'caregiversWithinRadius' in line:
        start=max(0,i-10)
        end=min(len(lines),i+40)
        for j in range(start,end):
            print(str(j+1)+': '+lines[j])
        break
