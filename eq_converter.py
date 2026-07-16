#!/usr/bin/env python3
"""
SpotifyEQ10 - dB to plist converter (Expanded 24dB Range)
"""

import plistlib
import sys

def db_to_value(db):
    """Convert dB (-24 to +24) to plist value (-2.0 to +2.0)"""
    return max(-2.0, min(2.0, db / 12.0))

def value_to_db(value):
    """Convert plist value (-2.0 to +2.0) to dB (-24 to +24)"""
    return value * 12.0

# Example presets (dB values mapped to the new expanded ceiling)
PRESETS = {
    "flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "bass_boost": [12, 10, 8, 4, 0, 0, 0, 0, 0, 0],
    "treble_boost": [0, 0, 0, 0, 0, 0, 4, 8, 10, 12],
    "v_shape": [10, 8, 4, 0, -4, -4, 0, 4, 8, 10],
    "vocal": [-4, -2, 0, 4, 8, 8, 4, 0, -2, -4],
    "rock": [8, 6, 4, 0, -2, -2, 0, 4, 6, 8],
    "electronic": [8, 6, 0, -4, -2, 0, 4, 6, 8, 6],
}

def create_plist(input_plist_path, output_plist_path, db_values):
    """Create modified plist with custom EQ values"""
    with open(input_plist_path, 'rb') as f:
        data = plistlib.load(f)
    
    eq_key = None
    for k in data.keys():
        if 'equalizer.values' in k:
            eq_key = k
            break
    
    if not eq_key:
        print("Error: equalizer.values key not found in plist")
        return False
    
    plist_values = [db_to_value(db) for db in db_values]
    data[eq_key] = plist_values
    
    with open(output_plist_path, 'wb') as f:
        plistlib.dump(data, f)
    
    print(f"Created: {output_plist_path}")
    print(f"dB values: {db_values}")
    print(f"Plist values: {[round(v, 3) for v in plist_values]}")
    return True

def print_usage():
    print("Usage:")
    print("  python eq_converter.py <input.plist> <output.plist> <preset_name>")
    print("  python eq_converter.py <input.plist> <output.plist> <db1> ... <db10>")
    print("\nAvailable presets:", ", ".join(PRESETS.keys()))

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print_usage()
        sys.exit(1)
    
    input_plist = sys.argv[1]
    output_plist = sys.argv[2]
    
    if len(sys.argv) == 4:
        preset_name = sys.argv[3].lower()
        if preset_name not in PRESETS:
            print(f"Unknown preset: {preset_name}")
            sys.exit(1)
        db_values = PRESETS[preset_name]
    else:
        try:
            db_values = [float(x) for x in sys.argv[3:13]]
            if len(db_values) < 10:
                db_values.extend([0] * (10 - len(db_values)))
        except ValueError:
            print("Error: dB values must be numbers")
            sys.exit(1)
    
    create_plist(input_plist, output_plist, db_values)
