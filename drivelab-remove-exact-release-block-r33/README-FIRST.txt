DRIVELAB EXACT BOTTOM RELEASE TEXT REMOVAL
==========================================

This package removes only the exact marked bottom block containing:

- Verified release
- DriveLab Telem 2.2.1 security check
- VirusTotal report

No other page content is edited. The script:

1. Requires exactly one DL-RELEASE-TRUST start marker and one end marker.
2. Confirms the marked block contains the exact release-security text.
3. Creates a timestamped backup of index.html.
4. Removes only the bytes between those two markers, including the markers.
5. Verifies every byte before and after the removed block is unchanged.
6. Restores the backup automatically if the write or validation fails.

Run:

  .\RUN-REMOVE-ONLY-BOTTOM-RELEASE-TEXT.bat

Then refresh https://drivelabregistration.org/ with Ctrl+F5.
