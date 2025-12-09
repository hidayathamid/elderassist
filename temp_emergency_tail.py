from pathlib import Path
path = Path('lib/screens/user/profile/profile_emergency_edit_screen.dart')
with path.open() as f:
    for i,line in enumerate(f,1):
        if 360 <= i <= 460:
            print(f'{i}: {line.rstrip()}')
