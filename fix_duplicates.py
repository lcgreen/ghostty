#!/usr/bin/env python3
"""
Script to fix duplicate file references in Xcode project.pbxproj file.
This removes duplicate entries in the PBXSourcesBuildPhase section.
"""

import re
import sys
from collections import defaultdict

def fix_xcode_duplicates(pbxproj_path):
    """Remove duplicate file references from PBXSourcesBuildPhase."""
    
    # Read the project file
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Backup the original
    backup_path = pbxproj_path + '.backup'
    with open(backup_path, 'w') as f:
        f.write(content)
    print(f"✓ Backup created at: {backup_path}")
    
    # Split content into lines for processing
    lines = content.split('\n')
    
    # Find PBXSourcesBuildPhase sections
    in_sources_section = False
    sources_start = -1
    sources_end = -1
    
    for i, line in enumerate(lines):
        if '/* Begin PBXSourcesBuildPhase section */' in line:
            sources_start = i
            in_sources_section = True
        elif '/* End PBXSourcesBuildPhase section */' in line:
            sources_end = i
            break
    
    if sources_start == -1 or sources_end == -1:
        print("✗ Could not find PBXSourcesBuildPhase section")
        return False
    
    print(f"✓ Found PBXSourcesBuildPhase section (lines {sources_start}-{sources_end})")
    
    # Process the sources section
    new_lines = lines[:sources_start + 1]
    seen_files = defaultdict(int)
    removed_count = 0
    
    i = sources_start + 1
    while i < sources_end:
        line = lines[i]
        
        # Check if this is a file reference line
        # Pattern: 			UUID /* filename in Sources */,
        match = re.search(r'/\*\s+(.+?)\s+in\s+Sources\s+\*/', line)
        
        if match:
            filename = match.group(1)
            seen_files[filename] += 1
            
            # Only keep the first occurrence of each file
            if seen_files[filename] == 1:
                new_lines.append(line)
            else:
                removed_count += 1
                print(f"  Removed duplicate: {filename} (occurrence #{seen_files[filename]})")
        else:
            # Keep non-file lines as-is
            new_lines.append(line)
        
        i += 1
    
    # Add the rest of the file
    new_lines.extend(lines[sources_end:])
    
    # Write the fixed content
    new_content = '\n'.join(new_lines)
    with open(pbxproj_path, 'w') as f:
        f.write(new_content)
    
    print(f"\n✓ Fixed! Removed {removed_count} duplicate file references")
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
