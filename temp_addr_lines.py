from pathlib import Path
path = Path('lib/screens/user/profile/profile_addresses_screen.dart')
with path.open() as f:
    for i,line in enumerate(f,1):
        if 430 <= i <= 480:
            print(f'{i}: {line.rstrip()}')
