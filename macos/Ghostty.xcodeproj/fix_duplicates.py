#!/usr/bin/env python3
"""
Script to fix duplicate file references in Xcode project.pbxproj file.
This removes duplicate entries from PBXBuildFile section.
"""

import re
import sys
from collections import defaultdict

def fix_xcode_duplicates(pbxproj_path):
    """Remove duplicate PBXBuildFile entries."""
    
    # Read the project file
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Backup the original
    backup_path = pbxproj_path + '.backup3'
    with open(backup_path, 'w') as f:
        f.write(content)
    print(f"✓ Backup created at: {backup_path}")
    
    # Split content into lines for processing
    lines = content.split('\n')
    
    # Find PBXBuildFile section
    build_file_start = -1
    build_file_end = -1
    
    for i, line in enumerate(lines):
        if '/* Begin PBXBuildFile section */' in line:
            build_file_start = i
        elif '/* End PBXBuildFile section */' in line:
            build_file_end = i
            break
    
    if build_file_start == -1 or build_file_end == -1:
        print("✗ Could not find PBXBuildFile section")
        return False
    
    print(f"✓ Found PBXBuildFile section (lines {build_file_start}-{build_file_end})")
    
    # Track which file references we've seen
    # Key: file reference UUID, Value: (filename, first line index)
    seen_build_files = {}
    removed_count = 0
    new_lines = lines[:build_file_start + 1]
    
    # Process the PBXBuildFile section
    i = build_file_start + 1
    while i < build_file_end:
        line = lines[i]
        
        # Pattern: UUID /* filename in Sources */ = {isa = PBXBuildFile; fileRef = FILE_UUID /* filename */; };
        match = re.search(r'^\s+([A-F0-9]{24})\s+/\*\s+(.+?)\s+in\s+Sources\s+\*/.*fileRef = ([A-F0-9]{24})', line)
        
        if match:
            build_file_uuid = match.group(1)
            filename = match.group(2)
            file_ref_uuid = match.group(3)
            
            # Check if we've already seen this file reference
            if file_ref_uuid in seen_build_files:
                removed_count += 1
                prev_filename = seen_build_files[file_ref_uuid]
                print(f"  Removed duplicate PBXBuildFile: {filename} (fileRef: {file_ref_uuid})")
                # Skip this line (don't add to new_lines)
            else:
                seen_build_files[file_ref_uuid] = filename
                new_lines.append(line)
        else:
            # Keep non-build-file lines
            new_lines.append(line)
        
        i += 1
    
    # Add the rest of the file
    new_lines.extend(lines[build_file_end:])
    
    # Write the fixed content
    new_content = '\n'.join(new_lines)
    with open(pbxproj_path, 'w') as f:
        f.write(new_content)
    
    print(f"\n✓ Fixed! Removed {removed_count} duplicate PBXBuildFile entries")
    print(f"✓ Original backed up to: {backup_path}")
    
    return True

if __name__ == '__main__':
    pbxproj_path = '/Users/lee.green/Projects/ghostty/macos/Ghostty.xcodeproj/project.pbxproj'
    
    if len(sys.argv) > 1:
        pbxproj_path = sys.argv[1]
    
    print(f"Fixing duplicates in: {pbxproj_path}\n")
    
    if fix_xcode_duplicates(pbxproj_path):
        print("\n✓ Done! You can now try building again with: zig build")
        print("\nIf something goes wrong, restore the backup with:")
        print(f"  cp {pbxproj_path}.backup {pbxproj_path}")
    else:
        print("\n✗ Failed to fix duplicates")
        sys.exit(1)
