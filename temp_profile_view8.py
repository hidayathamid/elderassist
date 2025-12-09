from pathlib import Path
path = Path('lib/screens/user/profile/profile_overview_screen.dart')
with path.open() as f:
    for i,line in enumerate(f,1):
        if 470 <= i <= 520:
            print(f'{i}: {line.rstrip()}')
